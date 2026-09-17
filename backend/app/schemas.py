import re
import uuid as uuid_lib
from datetime import date, datetime

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

from app.models import (
    ACCOUNT_TYPE_PRINCIPAL,
    ACCOUNT_TYPE_STUDENT,
    ACCOUNT_TYPE_TEACHER,
)
from app.security import MAX_PASSWORD_BYTES

_EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
_PHONE_CLEANUP_RE = re.compile(r"[\s\-()]")
_PHONE_RE = re.compile(r"^\+?\d{7,15}$")

# Every account_type the API accepts. One tuple rather than the same three-way
# comparison written out at each validator, so adding a fourth role later is a
# single edit and cannot be half-applied.
KNOWN_ACCOUNT_TYPES = (
    ACCOUNT_TYPE_TEACHER,
    ACCOUNT_TYPE_STUDENT,
    ACCOUNT_TYPE_PRINCIPAL,
)


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

    user_id: str
    uuid: uuid_lib.UUID
    full_name: str
    email: str | None
    phone: str | None

    # Null when the user signed in with Google or a phone number, neither of
    # which tells us whether they are a teacher or a student.
    account_type: int | None
    role: str | None

    # True while account_type is null — the app should send the user to the
    # "Who are you?" screen and then call PATCH /auth/me.
    needs_account_type: bool

    # True while the email or the phone number is missing. Every user has
    # both: signing up with one, the app asks for the other and sends it to
    # PATCH /auth/me.
    needs_contact_details: bool

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
    """Fills in what the sign-up route could not: a name and role after Google
    or phone sign-in, and whichever of email and phone the user did not sign up
    with.

    Every field is optional so the caller can set any of them, but a request
    that sets none is rejected rather than silently doing nothing.
    """

    full_name: str | None = Field(default=None, max_length=120)
    account_type: int | None = None
    email: str | None = Field(default=None, max_length=255)
    phone: str | None = Field(default=None, max_length=20)

    @field_validator("email")
    @classmethod
    def _check_email(cls, value: str | None) -> str | None:
        if value is None:
            return None
        email = value.strip().lower()
        if not looks_like_email(email):
            raise ValueError("Enter a valid email address")
        return email

    @field_validator("phone")
    @classmethod
    def _check_phone(cls, value: str | None) -> str | None:
        if value is None:
            return None
        phone = normalize_phone(value)
        if not is_valid_phone(phone):
            raise ValueError("Enter a valid phone number, e.g. +919876543210")
        return phone

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
        if value not in KNOWN_ACCOUNT_TYPES:
            raise ValueError(
                "account_type must be 0 (teacher), 1 (student) or 2 (principal)"
            )
        return value

    @model_validator(mode="after")
    def _requires_something_to_change(self) -> "ProfileUpdateRequest":
        if all(
            value is None
            for value in (self.full_name, self.account_type, self.email, self.phone)
        ):
            raise ValueError("Provide full_name, account_type, email, or phone")
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
        if value not in KNOWN_ACCOUNT_TYPES:
            raise ValueError(
                "account_type must be 0 (teacher), 1 (student) or 2 (principal)"
            )
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


# --- Students ----------------------------------------------------------------

_WHITESPACE_RE = re.compile(r"\s+")


def _clean_text(value: str) -> str:
    """Trimmed, with runs of whitespace collapsed to one space.

    Stored this way so "Meera  Sharma " and "Meera Sharma" are the same parent
    to the duplicate rule — the unique index compares what is stored.
    """
    return _WHITESPACE_RE.sub(" ", value).strip()


class StudentDetails(BaseModel):
    """Everything the register-student form collects about the child.

    Name and date of birth are required. The form insists on gender and address
    too, but a restored class file can legitimately lack them, and a restore
    that fails over a blank address would lose the whole class.

    Contact details are normalised on the way in: names and the address
    whitespace-collapsed, emails lower-cased, mobiles stripped of spaces and
    dashes. That is what makes the duplicate rule catch the same child typed
    slightly differently.
    """

    name: str = Field(min_length=1, max_length=120)
    date_of_birth: date
    gender: str = Field(default="", max_length=32)
    address: str = Field(default="", max_length=500)
    photo_path: str | None = Field(default=None, max_length=500)

    mother_name: str = Field(default="", max_length=120)
    mother_mobile: str = Field(default="", max_length=32)
    mother_email: str = Field(default="", max_length=255)

    father_name: str = Field(default="", max_length=120)
    father_mobile: str = Field(default="", max_length=32)
    father_email: str = Field(default="", max_length=255)

    guardian_name: str = Field(default="", max_length=120)
    guardian_relation: str = Field(default="", max_length=64)
    guardian_mobile: str = Field(default="", max_length=32)
    guardian_address: str = Field(default="", max_length=500)

    @field_validator(
        "name",
        "gender",
        "address",
        "mother_name",
        "father_name",
        "guardian_name",
        "guardian_relation",
        "guardian_address",
    )
    @classmethod
    def _clean(cls, value: str) -> str:
        return _clean_text(value)

    @field_validator("name")
    @classmethod
    def _name_not_blank(cls, value: str) -> str:
        if not value:
            raise ValueError("Student name cannot be blank")
        return value

    @field_validator("date_of_birth")
    @classmethod
    def _born_already(cls, value: date) -> date:
        if value > date.today():
            raise ValueError("Date of birth cannot be in the future")
        return value

    @field_validator("mother_email", "father_email")
    @classmethod
    def _clean_email(cls, value: str) -> str:
        email = value.strip().lower()
        if email and not looks_like_email(email):
            raise ValueError("Enter a valid email address")
        return email

    @field_validator("mother_mobile", "father_mobile", "guardian_mobile")
    @classmethod
    def _clean_mobile(cls, value: str) -> str:
        mobile = normalize_phone(value)
        if mobile and not is_valid_phone(mobile):
            raise ValueError("Enter a valid mobile number")
        return mobile


class StudentCreateRequest(StudentDetails):
    # Required: a student is always registered into a class.
    class_id: str = Field(min_length=1, max_length=16)


class ArchivedStudent(StudentDetails):
    """A student read out of a class file, on its way back in with a restore.

    No class_id — they belong to the class the restore creates. Their
    student_id is kept when it is one of ours, so a pupil keeps the id their
    paper registers already carry.
    """

    student_id: str | None = Field(default=None, max_length=16)


class StudentOut(StudentDetails):
    model_config = ConfigDict(from_attributes=True)

    student_id: str
    class_id: str

    # Alphabetical position in the class, from the class_roster view. It moves
    # when a student with an earlier name joins or one before them leaves.
    roll_number: int
    created_at: datetime


# --- Classes -----------------------------------------------------------------

# How many colours the app's GB_ClassPalette has. The server only checks the
# slot is in range; which colour a slot means is the app's business.
CLASS_COLOR_SLOTS = 9


def _clean_class_name(value: str) -> str:
    cleaned = _clean_text(value)
    if not cleaned:
        raise ValueError("Class name cannot be blank")
    return cleaned


def _known_color_slot(value: int) -> int:
    if not 0 <= value < CLASS_COLOR_SLOTS:
        raise ValueError(f"color_slot must be between 0 and {CLASS_COLOR_SLOTS - 1}")
    return value


class ClassOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    class_id: str
    name: str
    color_slot: int
    created_at: datetime

    # Who owns the class. The principal's dashboard lists every class in the
    # school, where two teachers each having a "Nursery" is normal — so without
    # the owner's name that list would be actively misleading.
    teacher_id: str

    # Joined in by the list endpoint only. Optional, so the routes that return
    # the ORM object straight back (create, update) still validate: there is no
    # such attribute on SchoolClass, and the default fills in.
    teacher_name: str | None = None


class ClassCreateRequest(BaseModel):
    name: str = Field(min_length=1, max_length=80)
    color_slot: int = 0

    # Empty for an ordinary new class. Filled only by "Restore class", with the
    # students read out of the uploaded class file, so the server can create
    # the class and its students in one transaction — all of it, or none.
    students: list[ArchivedStudent] = Field(default_factory=list)

    @field_validator("name")
    @classmethod
    def _strip_name(cls, value: str) -> str:
        return _clean_class_name(value)

    @field_validator("color_slot")
    @classmethod
    def _check_slot(cls, value: int) -> int:
        return _known_color_slot(value)


class ClassUpdateRequest(BaseModel):
    """What "Edit class" sends: the name, the colour, or both in one Save."""

    name: str | None = Field(default=None, min_length=1, max_length=80)
    color_slot: int | None = None

    @field_validator("name")
    @classmethod
    def _strip_name(cls, value: str | None) -> str | None:
        return None if value is None else _clean_class_name(value)

    @field_validator("color_slot")
    @classmethod
    def _check_slot(cls, value: int | None) -> int | None:
        return None if value is None else _known_color_slot(value)

    @model_validator(mode="after")
    def _requires_something_to_change(self) -> "ClassUpdateRequest":
        if self.name is None and self.color_slot is None:
            raise ValueError("Provide name, color_slot, or both")
        return self


class RosterEntry(BaseModel):
    """One row of the class_roster view — the "class table" as asked for."""

    model_config = ConfigDict(from_attributes=True)

    class_id: str
    class_name: str
    roll_number: int
    student_name: str
    student_id: str
