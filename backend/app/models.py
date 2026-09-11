import uuid as uuid_lib
from datetime import date, datetime

from sqlalchemy import (
    Boolean,
    CheckConstraint,
    Date,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    String,
    Uuid,
    func,
    text,
)
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base
from app.timeutils import utcnow

# Mirrors accountTypeTeacher / accountTypeStudent in GB_Constants.dart. The API
# still speaks these integers, so the app's sign-up and profile screens are
# unchanged; the database stores the role as lower-case text.
ACCOUNT_TYPE_TEACHER = 0
ACCOUNT_TYPE_STUDENT = 1

ROLE_TEACHER = "teacher"
ROLE_STUDENT = "student"

ACCOUNT_TYPE_TO_ROLE = {
    ACCOUNT_TYPE_TEACHER: ROLE_TEACHER,
    ACCOUNT_TYPE_STUDENT: ROLE_STUDENT,
}
ROLE_TO_ACCOUNT_TYPE = {role: number for number, role in ACCOUNT_TYPE_TO_ROLE.items()}


def _new_uuid() -> uuid_lib.UUID:
    return uuid_lib.uuid4()


class IdCounter(Base):
    """One row per id prefix (U, TR, CL, ST), holding the last number issued.

    See app/codes.py for why ids come from here rather than from counting rows.
    """

    __tablename__ = "id_counters"

    prefix: Mapped[str] = mapped_column(String(8), primary_key=True)
    last_value: Mapped[int] = mapped_column(Integer, default=0)


class User(Base):
    """Anyone who can sign in — a teacher, or (once the student portal exists) a
    parent.

    Keyed on a readable id, U_000001, with a random UUID alongside it. The
    readable id is what people quote and what other tables point at; the UUID is
    an identifier that reveals nothing about how many users exist, for anywhere
    an id has to be shown outside the app.

    Every user ends up with both an email and a phone number. Whichever one they
    signed up with is set straight away; the app then asks for the other. Both
    are nullable for the moments in between, and `needs_contact_details` is how
    the app knows to ask.
    """

    __tablename__ = "users"
    __table_args__ = (
        CheckConstraint(
            f"role IN ('{ROLE_TEACHER}', '{ROLE_STUDENT}')", name="ck_users_role"
        ),
    )

    user_id: Mapped[str] = mapped_column(String(16), primary_key=True)
    uuid: Mapped[uuid_lib.UUID] = mapped_column(
        Uuid, unique=True, default=_new_uuid
    )

    # Not part of the agreed schema's "username", but every screen that greets
    # the user needs it, and sign-up already collects it.
    full_name: Mapped[str] = mapped_column(String(120))

    # The "username": a user signs in with either. Emails are stored lower-case
    # and phones in +<country><number> form, so one person cannot end up with
    # two accounts over formatting.
    email: Mapped[str | None] = mapped_column(
        String(255), unique=True, index=True, default=None
    )
    phone: Mapped[str | None] = mapped_column(
        String(20), unique=True, index=True, default=None
    )

    # Null for accounts created through phone/OTP or Google, which have none.
    password_hash: Mapped[str | None] = mapped_column(String(255), default=None)

    # Google's "sub" claim: a permanent, unique id for the Google account. This
    # is the key we match on, not the email — see app/google_auth.py.
    google_id: Mapped[str | None] = mapped_column(
        String(255), unique=True, index=True, default=None
    )

    # 'teacher' or 'student', lower case. Null until chosen: Google and phone
    # sign-ins cannot tell us which, so the app asks afterwards.
    role: Mapped[str | None] = mapped_column(String(16), default=None)

    is_phone_verified: Mapped[bool] = mapped_column(Boolean, default=False)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)

    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)

    @property
    def account_type(self) -> int | None:
        return None if self.role is None else ROLE_TO_ACCOUNT_TYPE.get(self.role)

    @property
    def needs_account_type(self) -> bool:
        return self.role is None

    @property
    def needs_contact_details(self) -> bool:
        return self.email is None or self.phone is None


class Teacher(Base):
    """The teacher side of a user whose role is 'teacher'. TR_000001.

    Deliberately bare for now — the details a teacher profile will carry are
    still to be decided. What it is already for: classes belong to a teacher,
    not directly to a user, so the student portal can later give users a
    different kind of profile without classes having to change.

    The link runs from here to the user rather than from the user to here: a
    foreign key can only point at one table, and a user column holding either
    a TR_ or an ST_ id could never be one.
    """

    __tablename__ = "teachers"

    teacher_id: Mapped[str] = mapped_column(String(16), primary_key=True)
    uuid: Mapped[uuid_lib.UUID] = mapped_column(
        Uuid, unique=True, default=_new_uuid
    )
    # Unique: one user is at most one teacher.
    user_id: Mapped[str] = mapped_column(
        ForeignKey("users.user_id", ondelete="CASCADE"), unique=True
    )
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


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


class SchoolClass(Base):
    """A class on a teacher's dashboard. CL_000001.

    Owned by a teacher: two teachers each having a "Nursery" is normal, and
    neither should see the other's. Every query in the classes router filters on
    `teacher_id`, which is what makes that true.

    The roll numbers and student names that sit alongside a class are in the
    `class_roster` view (see app/database.py), not here — a class has to exist
    before its first student can be registered into it.
    """

    __tablename__ = "classes"
    __table_args__ = (
        # Case-insensitive: "nursery" and "Nursery" are the same tile to a
        # teacher. The router checks first to give a readable message; this is
        # what holds when two devices add the same name at the same moment.
        Index(
            "uq_classes_teacher_name",
            "teacher_id",
            func.lower(text("name")),
            unique=True,
        ),
    )

    class_id: Mapped[str] = mapped_column(String(16), primary_key=True)
    uuid: Mapped[uuid_lib.UUID] = mapped_column(
        Uuid, unique=True, default=_new_uuid
    )
    teacher_id: Mapped[str] = mapped_column(
        ForeignKey("teachers.teacher_id", ondelete="CASCADE"), index=True
    )
    name: Mapped[str] = mapped_column(String(80))

    # An index into GB_ClassPalette in the app, not a colour value. The palette
    # is a design decision that lives with the UI; storing the slot means a
    # retuned pastel reaches every existing class without a data migration.
    color_slot: Mapped[int] = mapped_column(Integer, default=0)

    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class Student(Base):
    """A pupil a teacher registered. ST_000001.

    Every column but the ids and the class is what the register-student form
    collects. The parent and guardian blocks are flattened into columns rather
    than given a contacts table: there are always exactly three fixed slots,
    each optional, and it matches the class file spreadsheet column for column.

    No roll number column. Roll numbers are alphabetical within a class and
    renumber when a student leaves, so they are worked out on every read by the
    `class_roster` view instead of being stored and kept up to date by hand.

    Optional text is stored as "" rather than NULL, and the contact details are
    stored normalised (see the classes router). Both matter for the duplicate
    rule below: a unique index treats two NULLs as different, and "Meera" and
    " meera" as different, and either would let a duplicate straight through.
    """

    __tablename__ = "students"
    __table_args__ = (
        # The duplicate rule: the same child registered twice has the same name,
        # class, date of birth, address, and parents' names, emails, and mobile
        # numbers. Twins share everything but the name, which is why the name is
        # part of the key — they are two students, and both are allowed.
        Index(
            "uq_students_same_child",
            "class_id",
            func.lower(text("name")),
            "date_of_birth",
            func.lower(text("address")),
            func.lower(text("mother_name")),
            func.lower(text("father_name")),
            "mother_email",
            "father_email",
            "mother_mobile",
            "father_mobile",
            unique=True,
        ),
    )

    student_id: Mapped[str] = mapped_column(String(16), primary_key=True)
    uuid: Mapped[uuid_lib.UUID] = mapped_column(
        Uuid, unique=True, default=_new_uuid
    )

    # Required: a student is always registered into a class. Deleting the class
    # deletes its students; the class file written first is what makes that
    # recoverable.
    class_id: Mapped[str] = mapped_column(
        ForeignKey("classes.class_id", ondelete="CASCADE"), index=True
    )

    name: Mapped[str] = mapped_column(String(120))

    # Stored as a date rather than an age, which would be wrong a year later.
    # The app works the age out from it.
    date_of_birth: Mapped[date] = mapped_column(Date)

    gender: Mapped[str] = mapped_column(String(32), default="")
    address: Mapped[str] = mapped_column(String(500), default="")

    # Waiting on the folder the profile images will come from. For now this is
    # a path on the device that picked the photo, which will not resolve on any
    # other device.
    photo_path: Mapped[str | None] = mapped_column(String(500), default=None)

    mother_name: Mapped[str] = mapped_column(String(120), default="")
    mother_mobile: Mapped[str] = mapped_column(String(32), default="")
    mother_email: Mapped[str] = mapped_column(String(255), default="")

    father_name: Mapped[str] = mapped_column(String(120), default="")
    father_mobile: Mapped[str] = mapped_column(String(32), default="")
    father_email: Mapped[str] = mapped_column(String(255), default="")

    guardian_name: Mapped[str] = mapped_column(String(120), default="")
    guardian_relation: Mapped[str] = mapped_column(String(64), default="")
    guardian_mobile: Mapped[str] = mapped_column(String(32), default="")
    guardian_address: Mapped[str] = mapped_column(String(500), default="")

    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)
