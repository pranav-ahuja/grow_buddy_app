import re
from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

from app.models import ACCOUNT_TYPE_STUDENT, ACCOUNT_TYPE_TEACHER
from app.security import MAX_PASSWORD_BYTES

_EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
_PHONE_CLEANUP_RE = re.compile(r"[\s\-()]")
_PHONE_RE = re.compile(r"^\+?\d{7,15}$")


def normalize_phone(raw: str) -> str:
    """Strip formatting so the same number always hits the same DB row.

    '+91 98765-43210' and '+919876543210' must not create two accounts.
    """
    return _PHONE_CLEANUP_RE.sub("", raw.strip())


def looks_like_email(value: str) -> bool:
    return bool(_EMAIL_RE.match(value.strip()))


def is_valid_phone(value: str) -> bool:
    return bool(_PHONE_RE.match(value))


class UserOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    full_name: str
    email: str | None
    phone: str | None

    # Null when the user signed in with Google or a phone number, neither of
    # which tells us whether they are a teacher or a student.
    account_type: int | None
    role: str | None

    # True while account_type is null — the app should send the user to the
    # "Who are you?" screen and then call PATCH /auth/me/account-type.
    needs_account_type: bool

    is_phone_verified: bool
    created_at: datetime


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: UserOut

    # True when this request created the account rather than signing in to an
    # existing one, so the app knows to show the profile-completion flow.
    is_new_user: bool = False


class GoogleLoginRequest(BaseModel):
    # The ID token from the google_sign_in plugin — NOT an email or a user id.
    # See app/google_auth.py for why that distinction matters.
    id_token: str = Field(min_length=1)


class ProfileUpdateRequest(BaseModel):
    """Fills in what Google and phone sign-ins cannot tell us.

    Both fields are optional so the caller can set either one, but a request
    that sets neither is rejected rather than silently doing nothing.
    """

    full_name: str | None = Field(default=None, max_length=120)
    account_type: int | None = None

    @field_validator("full_name")
    @classmethod
    def _strip_name(cls, value: str | None) -> str | None:
        if value is None:
            return None
        stripped = value.strip()
        if not stripped:
            raise ValueError("Full name cannot be blank")
        return stripped

    @field_validator("account_type")
    @classmethod
    def _known_account_type(cls, value: int | None) -> int | None:
        if value is None:
            return None
        if value not in (ACCOUNT_TYPE_TEACHER, ACCOUNT_TYPE_STUDENT):
            raise ValueError("account_type must be 0 (teacher) or 1 (student)")
        return value

    @model_validator(mode="after")
    def _requires_something_to_change(self) -> "ProfileUpdateRequest":
        if self.full_name is None and self.account_type is None:
            raise ValueError("Provide full_name, account_type, or both")
        return self


class SignUpRequest(BaseModel):
    full_name: str = Field(min_length=1, max_length=120)

    # The sign-up screen has a single "Email id / Phone Number" field, so the
    # server decides which one it received instead of duplicating that rule in
    # the Flutter client.
    identifier: str = Field(min_length=3, max_length=255)

    password: str = Field(min_length=8, max_length=MAX_PASSWORD_BYTES)

    # Required: the sign-up form has a teacher/student dropdown, so there is no
    # reason to guess here.
    account_type: int

    @field_validator("full_name")
    @classmethod
    def _strip_name(cls, value: str) -> str:
        stripped = value.strip()
        if not stripped:
            raise ValueError("Full name cannot be blank")
        return stripped

    @field_validator("account_type")
    @classmethod
    def _known_account_type(cls, value: int) -> int:
        if value not in (ACCOUNT_TYPE_TEACHER, ACCOUNT_TYPE_STUDENT):
            raise ValueError("account_type must be 0 (teacher) or 1 (student)")
        return value


class LoginRequest(BaseModel):
    email: str = Field(min_length=3, max_length=255)
    password: str = Field(min_length=1, max_length=MAX_PASSWORD_BYTES)


class OtpRequest(BaseModel):
    phone: str = Field(min_length=7, max_length=20)

    @field_validator("phone")
    @classmethod
    def _normalize(cls, value: str) -> str:
        phone = normalize_phone(value)
        if not is_valid_phone(phone):
            raise ValueError("Enter a valid phone number, e.g. +919876543210")
        return phone


class OtpRequestResponse(BaseModel):
    message: str
    expires_in_seconds: int
    # Populated only while OTP_DEBUG_RETURN is on, so phone login can be tested
    # before an SMS provider is wired up. Never set in production.
    debug_otp: str | None = None


class OtpVerifyRequest(OtpRequest):
    otp: str = Field(min_length=4, max_length=8)
    # Used only when the phone number has no account yet and one is created.
    full_name: str | None = Field(default=None, max_length=120)
