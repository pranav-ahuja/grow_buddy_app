import re
import uuid as uuid_lib
from datetime import date, datetime, time

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

from app.models import (
    ACCOUNT_TYPE_PRINCIPAL,
    ACCOUNT_TYPE_STUDENT,
    ACCOUNT_TYPE_TEACHER,
    ATTENDANCE_ABSENT,
    ATTENDANCE_PRESENT,
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

    # The class teacher — the one owner. **Null means unassigned**, which is a
    # class the principal has created and not yet handed to anyone, not a
    # broken row. The principal's dashboard lists every class in the school,
    # where two teachers each having a "Nursery" is normal, so without an
    # owner's name that list would be actively misleading.
    teacher_id: str | None = None

    # Joined in by the list endpoint only. Optional, so the routes that return
    # the ORM object straight back (create, update) still validate: there is no
    # such attribute on SchoolClass, and the default fills in.
    teacher_name: str | None = None

    # Everyone who teaches this class, the class teacher first. Filled by the
    # endpoints the class screen uses; empty elsewhere rather than absent, so
    # the app never has to distinguish "no co-teachers" from "not asked".
    teachers: list["ClassTeacherOut"] = Field(default_factory=list)


class ClassTeacherOut(BaseModel):
    """One teacher on a class, as the class screen and its picker read them."""

    teacher_id: str
    full_name: str

    # True for the one in `classes.teacher_id`. The picker highlights all of
    # them alike, but the class screen names the class teacher first and the
    # rest after — a room with two adults still has one who is answerable for
    # it.
    is_class_teacher: bool = False


class ClassCreateRequest(BaseModel):
    name: str = Field(min_length=1, max_length=80)
    color_slot: int = 0

    # The class teacher, **principal only**. Omitted or null creates an
    # unassigned class, which is the point of the field: an admin setting up
    # September does not yet know who is taking what.
    #
    # A teacher's own request ignores this — their class is theirs, and a
    # field that let them file one under a colleague would be a way to put
    # work on somebody else's dashboard.
    teacher_id: str | None = Field(default=None, max_length=16)

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


# --- Subjects ----------------------------------------------------------------


class SubjectCreateRequest(BaseModel):
    """Adding a subject, or proposing one.

    The same body either way — who is asking decides whether the result is
    approved or pending, not anything in the request. A teacher cannot ask for
    their proposal to arrive pre-approved because there is no field to ask with.
    """

    name: str = Field(min_length=1, max_length=80)

    @field_validator("name")
    @classmethod
    def _clean(cls, value: str) -> str:
        cleaned = _clean_text(value)
        if not cleaned:
            raise ValueError("Subject name cannot be blank")
        return cleaned


class SubjectOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    subject_id: str
    name: str

    # 'approved' or 'pending'. A pending subject is a teacher's proposal that
    # the principal has not acted on; nothing should be taught against it yet.
    status: str

    proposed_by_teacher_id: str | None
    approved_by_user_id: str | None
    approved_at: datetime | None
    created_at: datetime

    # Joined in by the list endpoint, so a principal reviewing proposals can
    # see who made them without a second request per row.
    proposed_by_name: str | None = None


# --- Attendance --------------------------------------------------------------


class AttendanceEntry(BaseModel):
    """One pupil's mark, inside a whole register."""

    student_id: str = Field(min_length=1, max_length=16)
    status: str = Field(min_length=1, max_length=1)

    @field_validator("status")
    @classmethod
    def _known_status(cls, value: str) -> str:
        mark = value.strip().upper()
        if mark not in (ATTENDANCE_PRESENT, ATTENDANCE_ABSENT):
            raise ValueError("status must be 'P' (present) or 'A' (absent)")
        return mark


class AttendanceMarkRequest(BaseModel):
    """A whole register: one class, one day, a mark per pupil.

    The register is taken in one request rather than one per child. A class of
    thirty would otherwise be thirty round trips, any of which could fail and
    leave the day half-marked — and a half-marked day reads as "the rest were
    absent", which is a different and much worse claim than "not taken yet".
    """

    class_id: str = Field(min_length=1, max_length=16)
    date: date
    entries: list[AttendanceEntry] = Field(min_length=1)

    @field_validator("date")
    @classmethod
    def _not_in_the_future(cls, value: date) -> date:
        if value > date.today():
            raise ValueError("Attendance cannot be taken for a future date")
        return value

    @model_validator(mode="after")
    def _one_mark_per_pupil(self) -> "AttendanceMarkRequest":
        seen = [entry.student_id for entry in self.entries]
        if len(set(seen)) != len(seen):
            raise ValueError("The same student appears twice in this register")
        return self


class AttendanceOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    student_id: str
    class_id: str
    teacher_id: str | None
    date: date
    status: str

    # Joined in so a register reads as names rather than ids.
    student_name: str | None = None


# --- Teacher profile ---------------------------------------------------------

_DIGITS_ONLY_RE = re.compile(r"\D")

# Long enough that nobody's real date of birth is refused, short enough that a
# typo like 1092 is.
MAX_TEACHER_AGE_YEARS = 100


def _clean_aadhaar(value: str) -> str:
    """Twelve digits, with whatever spacing the form allowed stripped off.

    People write Aadhaar as "1234 5678 9012". Stored bare, so the unique index
    treats the spaced and unspaced forms as the same number — otherwise one
    person could hold two teacher rows by typing it differently.
    """
    digits = _DIGITS_ONLY_RE.sub("", value)
    if len(digits) != 12:
        raise ValueError("An Aadhaar number is 12 digits")
    return digits


class TeacherExperienceCreateRequest(BaseModel):
    """One previous post."""

    school_name: str = Field(min_length=1, max_length=160)
    school_address: str = Field(default="", max_length=500)
    years: float = Field(ge=0, le=60)

    @field_validator("school_name", "school_address")
    @classmethod
    def _clean(cls, value: str) -> str:
        return _clean_text(value)

    @field_validator("school_name")
    @classmethod
    def _not_blank(cls, value: str) -> str:
        if not value:
            raise ValueError("School name cannot be blank")
        return value


class TeacherExperienceOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    school_name: str
    school_address: str
    years: float


class TeacherSubjectOut(BaseModel):
    """A subject on a teacher's record — just enough to name it."""

    subject_id: str
    name: str


class TeacherClassOut(BaseModel):
    """A class on a teacher's record."""

    class_id: str
    name: str


class TeacherOut(BaseModel):
    """A teacher's whole record, as the profile screen shows it.

    `full_name`, `email` and `phone` are joined from `users` rather than stored
    here — see the note on the Teacher model. So this object is assembled by
    the router, not validated straight off one row.
    """

    teacher_id: str
    user_id: str

    full_name: str
    email: str | None
    phone: str | None

    date_of_birth: date | None
    highest_qualification: str | None
    address: str | None
    relationship_status: str | None

    # The last four digits, and never more. The full number does not leave the
    # server: nothing in the app needs it, and a response carrying complete
    # Aadhaar numbers is a liability in every log and cache it passes through.
    aadhaar_last4: str | None

    emergency_contact_name: str | None
    emergency_contact_phone: str | None

    classes: list[TeacherClassOut]
    subjects: list[TeacherSubjectOut]
    experience: list[TeacherExperienceOut]

    # What the profile screen should still ask for. Aadhaar is excluded: it is
    # the one field a teacher may reasonably refuse, and counting it would nag
    # them forever over something optional.
    missing_profile_fields: list[str]
    is_profile_complete: bool

    created_at: datetime


class TeacherProfileUpdateRequest(BaseModel):
    """What the sign-up step and the profile screen send.

    Every field optional so either can send only what it collected, but a
    request that changes nothing is rejected rather than silently doing so.

    Absent and null mean different things: a field left out is untouched, and
    an explicit null clears it. Without that distinction a teacher could never
    remove an address they entered by mistake.
    """

    model_config = ConfigDict(extra="forbid")

    date_of_birth: date | None = None
    highest_qualification: str | None = Field(default=None, max_length=120)
    address: str | None = Field(default=None, max_length=500)
    relationship_status: str | None = Field(default=None, max_length=32)
    aadhaar_number: str | None = Field(default=None, max_length=20)
    emergency_contact_name: str | None = Field(default=None, max_length=120)
    emergency_contact_phone: str | None = Field(default=None, max_length=32)

    @field_validator("date_of_birth")
    @classmethod
    def _plausible(cls, value: date | None) -> date | None:
        if value is None:
            return None
        today = date.today()
        if value > today:
            raise ValueError("Date of birth cannot be in the future")
        if value.year < today.year - MAX_TEACHER_AGE_YEARS:
            raise ValueError("Please check the date of birth")
        return value

    @field_validator(
        "highest_qualification",
        "address",
        "relationship_status",
        "emergency_contact_name",
    )
    @classmethod
    def _clean_optional_text(cls, value: str | None) -> str | None:
        if value is None:
            return None
        # An empty string means "clear this", so it stays None rather than "".
        return _clean_text(value) or None

    @field_validator("aadhaar_number")
    @classmethod
    def _check_aadhaar(cls, value: str | None) -> str | None:
        if value is None or not value.strip():
            return None
        return _clean_aadhaar(value)

    @field_validator("emergency_contact_phone")
    @classmethod
    def _check_emergency_phone(cls, value: str | None) -> str | None:
        if value is None or not value.strip():
            return None
        phone = normalize_phone(value)
        if not is_valid_phone(phone):
            raise ValueError("Enter a valid phone number, e.g. +919876543210")
        return phone

    @model_validator(mode="after")
    def _requires_something(self) -> "TeacherProfileUpdateRequest":
        if not self.model_fields_set:
            raise ValueError(
                "Provide at least one of: date_of_birth, "
                "highest_qualification, address, relationship_status, "
                "aadhaar_number, emergency_contact_name, "
                "emergency_contact_phone"
            )
        return self


class TeacherSubjectsAssignRequest(BaseModel):
    """The principal setting which subjects a teacher teaches.

    The **whole set**, not an add or a remove. A screen with checkboxes knows
    what it wants the answer to be; asking it to work out the difference is how
    a half-applied edit leaves a subject assigned that the principal just
    unticked.
    """

    subject_ids: list[str] = Field(default_factory=list)

    @field_validator("subject_ids")
    @classmethod
    def _no_duplicates(cls, value: list[str]) -> list[str]:
        if len(set(value)) != len(value):
            raise ValueError("The same subject is listed twice")
        return value


class ClassTeacherAssignRequest(BaseModel):
    """The principal moving a class to a teacher."""

    teacher_id: str = Field(min_length=1, max_length=16)


# --- Guardians (parent accounts linked to a pupil) ---------------------------


class GuardianLinkRequest(BaseModel):
    """Staff linking a parent's account to a pupil.

    The account is named by email or phone rather than by `U_` id, because
    that is what a teacher has in front of them from the registration form.
    """

    identifier: str = Field(min_length=3, max_length=255)
    relation: str = Field(default="", max_length=32)

    @field_validator("relation")
    @classmethod
    def _clean_relation(cls, value: str) -> str:
        return _clean_text(value)


class GuardianOut(BaseModel):
    user_id: str
    student_id: str

    full_name: str
    email: str | None
    phone: str | None
    relation: str

    # Whether this account's email or phone is one of the contacts on the
    # pupil's own record. **Not** a permission check — the link is already
    # authorised by the staff member who made it. It shows which links the
    # registration form corroborates and which were typed in from elsewhere; a
    # parent who changed their number since registering is an ordinary false
    # negative, which is exactly why it cannot gate anything.
    matches_registered_contact: bool

    created_at: datetime


# --- Teaching assignments -----------------------------------------------------


class ClassTeachersAssignRequest(BaseModel):
    """The principal setting who teaches a class, from the class screen's
    "Add teacher" picker.

    **The whole set, not a difference.** A screen of names where the chosen
    ones are highlighted knows what it wants the answer to be; making it send
    a diff is how an unhighlighted teacher stays assigned. An empty list is a
    valid answer and means the class is unassigned — the same state a class is
    created in.

    The **first** id becomes the class teacher (`classes.teacher_id`) and the
    rest become co-teachers, with one exception: a class that already has a
    class teacher keeps them, as long as they are still in the set. Without
    that exception, reordering a list of checkboxes would quietly reassign
    who is answerable for the room.
    """

    teacher_ids: list[str] = Field(default_factory=list, max_length=20)

    @field_validator("teacher_ids")
    @classmethod
    def _no_duplicates(cls, value: list[str]) -> list[str]:
        if len(set(value)) != len(value):
            raise ValueError("The same teacher is listed twice")
        return value


# --- Approval requests --------------------------------------------------------


class ChangeRequestOut(BaseModel):
    """One row of the approval queue, for either side of it.

    The principal reads a list of these to decide from; the teacher reads
    their own to see what became of what they asked for. One shape, because
    they are looking at the same rows.
    """

    model_config = ConfigDict(from_attributes=True)

    id: int
    kind: str
    status: str

    # Who asked. The name is the stored copy, so it still reads correctly
    # after the teacher has left — see ChangeRequest.requested_by_name.
    requested_by_teacher_id: str | None
    requested_by_name: str

    # What it is about, where that still exists. Either can be null: a
    # class_create has no class until it is granted, and a granted
    # class_delete has none afterwards.
    class_id: str | None
    student_id: str | None

    # The one line to decide from: 'removal of the class "Nursery" and its 12
    # students'. Written when the request was raised, so it describes what was
    # asked even after the thing it names has gone.
    summary: str

    decided_by_user_id: str | None
    decided_at: datetime | None
    decision_note: str
    created_at: datetime

    # Deliberately **not** exposed: `payload`. It is the request's private
    # copy of a register-student form — a child's address and both parents'
    # numbers — and the queue only ever needs the summary to decide from.


class RequestDecisionRequest(BaseModel):
    """The principal's answer, when turning one down.

    The note is optional but asked for in the UI, because "rejected" with no
    reason is how a teacher asks again tomorrow in the same words.
    """

    note: str = Field(default="", max_length=500)

    @field_validator("note")
    @classmethod
    def _clean_note(cls, value: str) -> str:
        return _clean_text(value)


class ActionResult(BaseModel):
    """What came of a create or delete — done, or waiting on the principal.

    One shape for all four acts, because who is asking decides which of the
    two happens and the app should not need a different reader per role. The
    principal gets `status: "done"` and the thing itself; a teacher gets
    `status: "pending"` and the request that is now waiting.

    `detail` is the sentence to show. It is written by the server for the same
    reason every other message here is: the app would otherwise have to
    reproduce the rule about who needs approval in order to word its own
    snackbar, and be wrong the moment the rule changes.
    """

    status: str
    detail: str

    school_class: ClassOut | None = None
    student: StudentOut | None = None
    request: ChangeRequestOut | None = None


# --- Notifications ------------------------------------------------------------


class NotificationOut(BaseModel):
    """One line in the notification tab."""

    model_config = ConfigDict(from_attributes=True)

    id: int

    # Separate, as stored: the tab groups by day and stamps each line with a
    # clock time. See the Notification model for why they are not one column.
    date: date
    time: time

    # Where it came from, in words — a teacher's name, or "GrowBuddy".
    source: str

    # "user" or "broadcast". Sent so the app can mark a school-wide notice as
    # such; a broadcast reads differently from something addressed to you.
    audience: str

    message: str

    # Set where this line is an approval the reader can decide on the spot.
    # Null for anything that is only news.
    request_id: int | None

    read_at: datetime | None
    created_at: datetime


class NotificationListOut(BaseModel):
    """The tab's contents, plus the two numbers its badges need.

    Counted on the server rather than by the app. The unread count has to
    match what the list would show, and two independent counts of the same
    thing eventually disagree — usually at the worst moment, when the badge
    says 3 and the list is empty.
    """

    notifications: list[NotificationOut]

    # The dot on the bell.
    unread: int

    # The principal's queue depth, and **zero for everyone else** — a teacher
    # has no business knowing how many requests the school is sitting on.
    pending_requests: int
