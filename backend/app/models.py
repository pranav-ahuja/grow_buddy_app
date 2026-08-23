from datetime import datetime

from sqlalchemy import Boolean, DateTime, Integer, String
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base
from app.timeutils import utcnow

# Mirrors accountTypeTeacher / accountTypeStudent in GB_Constants.dart.
ACCOUNT_TYPE_TEACHER = 0
ACCOUNT_TYPE_STUDENT = 1

ACCOUNT_TYPE_LABELS = {
    ACCOUNT_TYPE_TEACHER: "teacher",
    ACCOUNT_TYPE_STUDENT: "student",
}


class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(primary_key=True)
    full_name: Mapped[str] = mapped_column(String(120))

    # A user signs up with an email or a phone number, so either column may be
    # empty — but at least one is always set (enforced in the signup route).
    email: Mapped[str | None] = mapped_column(
        String(255), unique=True, index=True, default=None
    )
    phone: Mapped[str | None] = mapped_column(
        String(20), unique=True, index=True, default=None
    )

    # Null for accounts created through phone/OTP or Google login, which have
    # no password.
    hashed_password: Mapped[str | None] = mapped_column(String(255), default=None)

    # Google's "sub" claim: a permanent, unique id for the Google account. This
    # is the key we match on, not the email — see app/google_auth.py.
    google_id: Mapped[str | None] = mapped_column(
        String(255), unique=True, index=True, default=None
    )

    # Null until the user picks teacher or student. Google and phone sign-ins
    # cannot tell us which, so the app asks afterwards rather than guessing.
    account_type: Mapped[int | None] = mapped_column(Integer, default=None)

    is_phone_verified: Mapped[bool] = mapped_column(Boolean, default=False)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)

    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)

    @property
    def role(self) -> str | None:
        if self.account_type is None:
            return None
        return ACCOUNT_TYPE_LABELS.get(self.account_type)

    @property
    def needs_account_type(self) -> bool:
        return self.account_type is None


class OtpCode(Base):
    """A one-time password issued for a phone number.

    The code itself is hashed, so a leaked database still cannot be used to log
    in as somebody mid-flow.
    """

    __tablename__ = "otp_codes"

    id: Mapped[int] = mapped_column(primary_key=True)
    phone: Mapped[str] = mapped_column(String(20), index=True)
    code_hash: Mapped[str] = mapped_column(String(255))
    expires_at: Mapped[datetime] = mapped_column(DateTime)
    attempts: Mapped[int] = mapped_column(Integer, default=0)
    consumed_at: Mapped[datetime | None] = mapped_column(DateTime, default=None)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)

    def is_usable(self, now: datetime, max_attempts: int) -> bool:
        return (
            self.consumed_at is None
            and self.expires_at > now
            and self.attempts < max_attempts
        )


class PasswordResetCode(Base):
    """A one-time code emailed to prove someone owns an address before the
    password behind it is changed.

    Deliberately its own table rather than a `purpose` column on OtpCode: an
    OtpCode is redeemable for a full login token, and the two must never be
    confusable. This one is keyed by email and only ever unlocks a password
    change.

    Two timestamps rather than one because the flow has two steps. `verified_at`
    records that the right code was entered — the point where a reset token is
    issued — and `consumed_at` records that the token was spent on an actual
    password change, which is what makes it single-use.
    """

    __tablename__ = "password_reset_codes"

    id: Mapped[int] = mapped_column(primary_key=True)
    email: Mapped[str] = mapped_column(String(255), index=True)
    code_hash: Mapped[str] = mapped_column(String(255))
    expires_at: Mapped[datetime] = mapped_column(DateTime)
    attempts: Mapped[int] = mapped_column(Integer, default=0)
    verified_at: Mapped[datetime | None] = mapped_column(DateTime, default=None)
    consumed_at: Mapped[datetime | None] = mapped_column(DateTime, default=None)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)

    def is_usable(self, now: datetime, max_attempts: int) -> bool:
        return (
            self.consumed_at is None
            and self.expires_at > now
            and self.attempts < max_attempts
        )
