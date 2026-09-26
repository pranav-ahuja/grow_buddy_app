import logging
from datetime import timedelta

from fastapi import APIRouter, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.accounts import apply_role, new_user
from app.config import settings
from app.deps import CurrentUser, DbSession
from app.models import (
    ACCOUNT_TYPE_TO_ROLE,
    CONTACT_CHANNEL_PHONE,
    ContactChangeCode,
    OtpCode,
    User,
)
from app.google_auth import GoogleAuthError, GoogleProfile, verify_google_id_token
from app.schemas import (
    ContactChangeRequest,
    ContactChangeResponse,
    ContactChangeVerifyRequest,
    GoogleLoginRequest,
    LoginRequest,
    OtpRequest,
    OtpRequestResponse,
    OtpVerifyRequest,
    ProfileUpdateRequest,
    SignUpRequest,
    TokenResponse,
    UserOut,
    is_valid_phone,
    looks_like_email,
    normalize_phone,
)
from app.security import (
    create_access_token,
    generate_otp,
    hash_otp,
    hash_password,
    verify_otp,
    verify_password,
)
from app.timeutils import utcnow

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/auth", tags=["auth"])

# Minimum gap between two OTP requests for the same number, so the endpoint
# cannot be used to spam somebody (or to burn SMS credits) in a loop.
OTP_RESEND_COOLDOWN_SECONDS = 30

# Stand-in used when an identity source gives us no name. Treated as "unset",
# so it can be overwritten by a real one.
PLACEHOLDER_FULL_NAME = "GrowBuddy User"


def _sync_google_profile(db: Session, user: User, profile: GoogleProfile) -> None:
    """Refresh the attributes Google owns on a user we have already identified.

    The account is identified by `google_id`, so a changed email means the same
    person with a new address — not a new account. Without this the stored email
    would go stale forever and email/password login would break for them.
    """
    if profile.email_verified and profile.email and profile.email != user.email:
        # The email column is unique, so an address already spoken for cannot be
        # moved here. Rare (mostly reassigned Workspace addresses), and never a
        # reason to block a sign-in: google_id still identifies them correctly.
        taken_by = db.scalar(
            select(User).where(
                User.email == profile.email, User.user_id != user.user_id
            )
        )
        if taken_by is None:
            user.email = profile.email
        else:
            logger.warning(
                "Google account %s now reports %s, already registered to user %s. "
                "Keeping the existing address on user %s.",
                user.google_id,
                profile.email,
                taken_by.user_id,
                user.user_id,
            )

    # Only fill in a name we never really had. Overwriting one the user chose in
    # our own app with their Google profile name would be surprising.
    if profile.full_name and user.full_name in ("", PLACEHOLDER_FULL_NAME):
        user.full_name = profile.full_name


def _token_response(user: User, *, is_new_user: bool = False) -> TokenResponse:
    return TokenResponse(
        access_token=create_access_token(user.user_id),
        user=UserOut.model_validate(user),
        is_new_user=is_new_user,
    )


@router.post("/signup", response_model=TokenResponse, status_code=status.HTTP_201_CREATED)
def signup(payload: SignUpRequest, db: DbSession) -> TokenResponse:
    identifier = payload.identifier.strip()

    email: str | None = None
    phone: str | None = None

    if looks_like_email(identifier):
        email = identifier.lower()
    else:
        candidate = normalize_phone(identifier)
        if not is_valid_phone(candidate):
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="Enter a valid email address or phone number",
            )
        phone = candidate

    existing = db.scalar(
        select(User).where(
            (User.email == email) if email else (User.phone == phone)
        )
    )
    if existing is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="An account with those details already exists",
        )

    user = new_user(
        db,
        full_name=payload.full_name,
        email=email,
        phone=phone,
        password_hash=hash_password(payload.password),
    )
    apply_role(db, user, ACCOUNT_TYPE_TO_ROLE[payload.account_type])
    db.commit()
    db.refresh(user)

    return _token_response(user, is_new_user=True)


@router.post("/login", response_model=TokenResponse)
def login(payload: LoginRequest, db: DbSession) -> TokenResponse:
    identifier = payload.email.strip()

    if looks_like_email(identifier):
        user = db.scalar(select(User).where(User.email == identifier.lower()))
    else:
        user = db.scalar(select(User).where(User.phone == normalize_phone(identifier)))

    # One message for "no such user" and "wrong password" alike, so the endpoint
    # cannot be used to discover which emails are registered.
    if user is None or not verify_password(payload.password, user.password_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid email or password",
        )

    if not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="This account has been disabled",
        )

    return _token_response(user)


@router.post("/otp/request", response_model=OtpRequestResponse)
def request_otp(payload: OtpRequest, db: DbSession) -> OtpRequestResponse:
    now = utcnow()

    latest = db.scalar(
        select(OtpCode)
        .where(OtpCode.phone == payload.phone)
        .order_by(OtpCode.created_at.desc(), OtpCode.id.desc())
    )
    if latest is not None:
        elapsed = (now - latest.created_at).total_seconds()
        if latest.consumed_at is None and elapsed < OTP_RESEND_COOLDOWN_SECONDS:
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail=(
                    "Please wait "
                    f"{int(OTP_RESEND_COOLDOWN_SECONDS - elapsed)}s "
                    "before requesting another code"
                ),
            )

    # Retire any outstanding codes so only the newest one can be redeemed.
    for stale in db.scalars(
        select(OtpCode).where(
            OtpCode.phone == payload.phone, OtpCode.consumed_at.is_(None)
        )
    ):
        stale.consumed_at = now

    code = generate_otp()
    db.add(
        OtpCode(
            phone=payload.phone,
            code_hash=hash_otp(code),
            expires_at=now + timedelta(minutes=settings.otp_expire_minutes),
        )
    )
    db.commit()

    # TODO: send `code` over SMS (MSG91 / Twilio) instead of logging it.
    logger.info("OTP for %s is %s", payload.phone, code)

    return OtpRequestResponse(
        message="Verification code sent",
        expires_in_seconds=settings.otp_expire_minutes * 60,
        debug_otp=code if settings.otp_debug_return else None,
    )


@router.post("/otp/verify", response_model=TokenResponse)
def verify_otp_code(payload: OtpVerifyRequest, db: DbSession) -> TokenResponse:
    now = utcnow()

    record = db.scalar(
        select(OtpCode)
        .where(OtpCode.phone == payload.phone, OtpCode.consumed_at.is_(None))
        .order_by(OtpCode.created_at.desc(), OtpCode.id.desc())
    )

    if record is None or not record.is_usable(now, settings.otp_max_attempts):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="This code has expired. Please request a new one.",
        )

    if not verify_otp(payload.otp, record.code_hash):
        record.attempts += 1
        db.commit()
        remaining = settings.otp_max_attempts - record.attempts
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=(
                f"Incorrect code. {remaining} attempt(s) left."
                if remaining > 0
                else "Too many incorrect attempts. Please request a new code."
            ),
        )

    record.consumed_at = now

    user = db.scalar(select(User).where(User.phone == payload.phone))
    is_new_user = user is None
    if user is None:
        # Phone login doubles as sign-up: first successful OTP creates the
        # account. Name is optional here because the OTP screen never asks, and
        # the role stays null until the user picks teacher or student.
        user = new_user(
            db,
            full_name=(payload.full_name or "").strip() or PLACEHOLDER_FULL_NAME,
            phone=payload.phone,
            is_phone_verified=True,
        )
    else:
        user.is_phone_verified = True

    db.commit()
    db.refresh(user)

    return _token_response(user, is_new_user=is_new_user)


@router.post("/google", response_model=TokenResponse)
def google_login(payload: GoogleLoginRequest, db: DbSession) -> TokenResponse:
    """Sign in (or sign up) with a Google ID token.

    Deciding whether this is a first login is a three-step lookup:

    1. Match on `google_id` — the token's "sub" claim. This is the right key
       because Google guarantees it is unique and never changes, even if the
       person renames their Gmail address.
    2. Otherwise match on a *verified* email. That means the person already has
       a GrowBuddy account from the password or phone flow and is now using the
       Google button; we link the two rather than creating a duplicate.
    3. Otherwise it really is a new account, so create one.

    Matching on email alone (step 2 only) is the tempting shortcut, but emails
    are re-assignable and users can change theirs — `sub` cannot.
    """
    try:
        profile = verify_google_id_token(
            payload.id_token, settings.google_client_id_list
        )
    except GoogleAuthError as error:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=str(error),
        ) from error

    is_new_user = False

    # An address Google has not confirmed proves nothing about who is holding
    # the phone, so it is never used to find or fill in an account.
    trusted_email = profile.email if profile.email_verified else None

    user = db.scalar(select(User).where(User.google_id == profile.google_id))

    if user is None and trusted_email:
        # Step 2: the person already has a password or phone account and is now
        # using the Google button. Link the two instead of making a duplicate.
        user = db.scalar(select(User).where(User.email == trusted_email))
        if user is not None:
            user.google_id = profile.google_id

    if user is not None:
        # Only meaningful for an account that already exists. Checking after the
        # `User(...)` below would always fail: SQLAlchemy column defaults are
        # applied by the database on INSERT, so `is_active` is still None on a
        # freshly constructed object.
        if not user.is_active:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="This account has been disabled",
            )
        _sync_google_profile(db, user, profile)

    if user is None:
        if profile.email and not profile.email_verified:
            # Someone else already holds this address. Creating a second
            # account would break the unique-email constraint, and linking on
            # an unverified claim would hand over their account.
            clash = db.scalar(select(User).where(User.email == profile.email))
            if clash is not None:
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail=(
                        "An account already uses that email address, and Google "
                        "has not verified it. Please log in with your password."
                    ),
                )

        is_new_user = True
        user = new_user(
            db,
            full_name=profile.full_name or PLACEHOLDER_FULL_NAME,
            email=trusted_email,
            google_id=profile.google_id,
        )

    db.commit()
    db.refresh(user)

    return _token_response(user, is_new_user=is_new_user)


@router.get("/me", response_model=UserOut)
def me(current_user: CurrentUser) -> User:
    return current_user


@router.patch("/me", response_model=UserOut)
def update_profile(
    payload: ProfileUpdateRequest, current_user: CurrentUser, db: DbSession
) -> User:
    """Complete a profile after sign-up.

    What the profile screen calls once the user has entered what sign-up could
    not collect: a name and teacher/student after Google or phone sign-in, and
    the email or phone number they did not sign up with. Fields left out are
    left alone.
    """
    if payload.email is not None and payload.email != current_user.email:
        _reject_taken(db, User.email == payload.email, current_user, "email address")
        current_user.email = payload.email

    if payload.phone is not None and payload.phone != current_user.phone:
        _reject_taken(db, User.phone == payload.phone, current_user, "phone number")
        current_user.phone = payload.phone
        # A number typed into a form proves nothing about who holds the phone.
        # Only the OTP flow sets this true.
        current_user.is_phone_verified = False

    if payload.full_name is not None:
        current_user.full_name = payload.full_name
    if payload.account_type is not None:
        apply_role(db, current_user, ACCOUNT_TYPE_TO_ROLE[payload.account_type])

    db.commit()
    db.refresh(current_user)
    return current_user


def _reject_taken(db: Session, clause, current_user: User, what: str) -> None:
    """409 when another account already holds this email or phone.

    Both columns are unique, so letting the write through would fail anyway —
    this turns that into a message the profile screen can show.
    """
    holder = db.scalar(select(User).where(clause, User.user_id != current_user.user_id))
    if holder is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"That {what} is already used by another account",
        )


@router.post("/me/contact/request", response_model=ContactChangeResponse)
def request_contact_change(
    payload: ContactChangeRequest, current_user: CurrentUser, db: DbSession
) -> ContactChangeResponse:
    """Send a code to an email or number the signed-in user wants to move to.

    **Nothing on `users` changes here.** The value is parked on a
    `contact_change_codes` row and only reaches the account when
    `verify_contact_change` redeems the code. Until then the old email and
    number are still what sign-in looks up, which is the point: a mistyped
    number that is never confirmed costs the user a second attempt, not their
    way back into the account.

    Authenticated, unlike `/auth/otp/request`. That route has to be open —
    it is how phone login starts — and it finds the account from the number in
    the request. This one already knows whose contact is changing, so the
    number in the request is a claim about the future, not a lookup key.
    """
    now = utcnow()
    channel = payload.channel
    value = payload.value

    current = (
        current_user.phone if channel == CONTACT_CHANNEL_PHONE else current_user.email
    )
    if current is not None and current == value:
        # Not an error worth a 409: there is simply nothing to prove. Telling
        # the user their number is already their number is more useful than
        # sending them a code to confirm a change that is not one.
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=(
                "That is already your phone number"
                if channel == CONTACT_CHANNEL_PHONE
                else "That is already your email address"
            ),
        )

    # Checked now so the user is told before waiting for a code that can never
    # be redeemed. Checked *again* at verify time, because these rows are
    # unique and somebody else may sign up with it in between — the same reason
    # app/approvals.py re-validates a request when it is granted.
    _reject_contact_taken(db, channel, value, current_user)

    latest = db.scalar(
        select(ContactChangeCode)
        .where(
            ContactChangeCode.user_id == current_user.user_id,
            ContactChangeCode.channel == channel,
        )
        .order_by(ContactChangeCode.created_at.desc(), ContactChangeCode.id.desc())
    )
    if latest is not None:
        elapsed = (now - latest.created_at).total_seconds()
        if latest.consumed_at is None and elapsed < OTP_RESEND_COOLDOWN_SECONDS:
            # The same cooldown, from the same constant, as phone login: a code
            # costs an SMS whoever asked for it, and the app's resend timer
            # counts down from this number.
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail=(
                    "Please wait "
                    f"{int(OTP_RESEND_COOLDOWN_SECONDS - elapsed)}s "
                    "before requesting another code"
                ),
            )

    # Retire this user's outstanding codes on this channel, so only the newest
    # can be redeemed — and so changing the number twice cannot leave the first
    # attempt's code still able to commit the first number.
    for stale in db.scalars(
        select(ContactChangeCode).where(
            ContactChangeCode.user_id == current_user.user_id,
            ContactChangeCode.channel == channel,
            ContactChangeCode.consumed_at.is_(None),
        )
    ):
        stale.consumed_at = now

    code = generate_otp()
    db.add(
        ContactChangeCode(
            user_id=current_user.user_id,
            channel=channel,
            new_value=value,
            code_hash=hash_otp(code),
            expires_at=now + timedelta(minutes=settings.otp_expire_minutes),
        )
    )
    db.commit()

    # TODO: send `code` over SMS (MSG91 / Twilio) or email (SES / SMTP) instead
    # of logging it — the same gap request_otp() has, and the same reason
    # OTP_DEBUG_RETURN exists.
    logger.info("Contact-change code for %s (%s) is %s", value, channel, code)

    return ContactChangeResponse(
        message="Verification code sent",
        channel=channel,
        value=value,
        expires_in_seconds=settings.otp_expire_minutes * 60,
        debug_otp=code if settings.otp_debug_return else None,
    )


@router.post("/me/contact/verify", response_model=UserOut)
def verify_contact_change(
    payload: ContactChangeVerifyRequest, current_user: CurrentUser, db: DbSession
) -> User:
    """Redeem a code and move the contact onto the account.

    This is the write that makes the new email or number the one sign-in uses,
    and it is deliberately the only one: the value committed is the value the
    code was issued for, read off the row, never re-read from the request.

    A phone change also sets `is_phone_verified`, which is the honest meaning of
    that flag — a code reached the number and came back. `PATCH /auth/me` clears
    it because a number typed into a form proves nothing; this route is the
    proof.
    """
    now = utcnow()
    channel = payload.channel

    record = db.scalar(
        select(ContactChangeCode)
        .where(
            ContactChangeCode.user_id == current_user.user_id,
            ContactChangeCode.channel == channel,
            ContactChangeCode.consumed_at.is_(None),
        )
        .order_by(ContactChangeCode.created_at.desc(), ContactChangeCode.id.desc())
    )

    if record is None or not record.is_usable(now, settings.otp_max_attempts):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="This code has expired. Please request a new one.",
        )

    if not verify_otp(payload.otp, record.code_hash):
        record.attempts += 1
        db.commit()
        remaining = settings.otp_max_attempts - record.attempts
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=(
                f"Incorrect code. {remaining} attempt(s) left."
                if remaining > 0
                else "Too many incorrect attempts. Please request a new code."
            ),
        )

    # Re-checked against the school as it is now, not as it was when the code
    # was sent. Both columns are unique, so an address claimed in between would
    # otherwise turn a correct code into a 500 from the database.
    _reject_contact_taken(db, channel, record.new_value, current_user)

    record.consumed_at = now

    if channel == CONTACT_CHANNEL_PHONE:
        current_user.phone = record.new_value
        # Earned, not assumed: a code went to this number and came back.
        current_user.is_phone_verified = True
    else:
        current_user.email = record.new_value

    db.commit()
    db.refresh(current_user)
    return current_user


def _reject_contact_taken(
    db: Session, channel: str, value: str, current_user: User
) -> None:
    """409 when another account already holds this email or number.

    Shares its reasoning with `_reject_taken`, but not its signature: this one
    picks the column from the channel, so the caller cannot accidentally check
    the email column for a phone change.
    """
    clause = (
        User.phone == value if channel == CONTACT_CHANNEL_PHONE else User.email == value
    )
    _reject_taken(
        db,
        clause,
        current_user,
        "phone number" if channel == CONTACT_CHANNEL_PHONE else "email address",
    )
