import uuid as uuid_lib
from datetime import date, datetime
from decimal import Decimal

from sqlalchemy import (
    Boolean,
    CheckConstraint,
    Date,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    Numeric,
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

# The principal, who is this school's admin. Added as 2 rather than renumbering:
# 0 and 1 are already written into every existing row and into the app's
# GB_Constants.dart, and shifting them would silently re-role every account.
ACCOUNT_TYPE_PRINCIPAL = 2

ROLE_TEACHER = "teacher"
ROLE_STUDENT = "student"
ROLE_PRINCIPAL = "principal"

ACCOUNT_TYPE_TO_ROLE = {
    ACCOUNT_TYPE_TEACHER: ROLE_TEACHER,
    ACCOUNT_TYPE_STUDENT: ROLE_STUDENT,
    ACCOUNT_TYPE_PRINCIPAL: ROLE_PRINCIPAL,
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
    """Anyone who can sign in — a teacher, the principal, or (once the student
    portal exists) a parent on their child's behalf.

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
            f"role IN ('{ROLE_TEACHER}', '{ROLE_STUDENT}', '{ROLE_PRINCIPAL}')",
            name="ck_users_role",
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

    # 'teacher', 'student' or 'principal', lower case. Null until chosen:
    # Google and phone sign-ins cannot tell us which, so the app asks
    # afterwards.
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

    Classes belong to a teacher, not directly to a user, so the student portal
    can later give users a different kind of profile without classes having to
    change. The link runs from here to the user rather than from the user to
    here: a foreign key can only point at one table, and a user column holding
    either a TR_ or an ST_ id could never be one.

    **Name and phone are deliberately not here.** They are on `users`, where
    signing in already reads them, and they are served with this profile by
    joining rather than copying. A second copy is a second thing to keep in
    step, and the failure is a profile that disagrees with the account someone
    logs in with.

    Every column below is **nullable**. Teacher rows already existed before
    this profile did, and a sign-up cannot retroactively collect a date of
    birth — a migration that demanded one could not have run at all.
    [missing_profile_fields] is how the app knows what is still to ask for.

    The repeating parts are their own tables: [TeacherExperience] because a
    teacher has several previous schools, and [TeacherSubject] because subjects
    and teachers are many-to-many. Classes need neither — `classes.teacher_id`
    already makes one teacher's classes a list.
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

    date_of_birth: Mapped[date | None] = mapped_column(Date, default=None)
    highest_qualification: Mapped[str | None] = mapped_column(
        String(120), default=None
    )
    address: Mapped[str | None] = mapped_column(String(500), default=None)

    # Free text rather than a CHECK. The app offers a dropdown, but the set of
    # answers people give to this is not ours to close, and a constraint here
    # would turn "something the form does not list" into a 500.
    relationship_status: Mapped[str | None] = mapped_column(
        String(32), default=None
    )

    # Twelve digits, unique — one Aadhaar belongs to one person.
    #
    # **Never returned in full by the API.** `TeacherOut` exposes the last four
    # digits only, because nothing in the app needs the rest and a table of
    # complete Aadhaar numbers is a serious liability if it is ever read by
    # someone who should not have it. Storing it at all is worth a deliberate
    # decision: UIDAI's rules restrict both storing and displaying it.
    aadhaar_number: Mapped[str | None] = mapped_column(
        String(12), unique=True, default=None
    )

    emergency_contact_name: Mapped[str | None] = mapped_column(
        String(120), default=None
    )
    emergency_contact_phone: Mapped[str | None] = mapped_column(
        String(32), default=None
    )

    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)

    # The fields a complete profile has. Not a CHECK or a NOT NULL: the profile
    # is filled in over time, and the app asks for what is missing rather than
    # refusing to store a partial one.
    PROFILE_FIELDS = (
        "date_of_birth",
        "highest_qualification",
        "address",
        "relationship_status",
        "emergency_contact_name",
        "emergency_contact_phone",
    )

    @property
    def missing_profile_fields(self) -> list[str]:
        """What the profile screen should still ask for.

        Aadhaar is left out on purpose. It is the one field a teacher may
        reasonably refuse to give, and marking a profile permanently
        "incomplete" over it would nag them forever for something optional.
        """
        return [
            field
            for field in self.PROFILE_FIELDS
            if not getattr(self, field, None)
        ]

    @property
    def is_profile_complete(self) -> bool:
        return not self.missing_profile_fields

    @property
    def aadhaar_last4(self) -> str | None:
        """The only part of the Aadhaar number that leaves the server."""
        if not self.aadhaar_number:
            return None
        return self.aadhaar_number[-4:]


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


# Attendance is recorded one character at a time, as the requirement states:
# P for present, A for absent. Kept as the stored values rather than a boolean
# so a third state — 'L' for late, say — is a CHECK change and not a column
# type change.
ATTENDANCE_PRESENT = "P"
ATTENDANCE_ABSENT = "A"

# A subject proposed by a teacher waits for the principal; one the principal
# adds is approved the moment it exists.
SUBJECT_PENDING = "pending"
SUBJECT_APPROVED = "approved"


class Subject(Base):
    """A subject that can be taught. S_000001.

    School-wide, not per class or per teacher: "Mathematics" is one subject
    that many classes have, so the name is unique across the school
    (case-insensitively, like class names are per teacher).

    **Two ways in, and that is the point.** The principal adds a subject and it
    is approved immediately. A teacher may also propose one, which lands as
    `pending` and does nothing until the principal approves it — the two-way
    check the requirements ask for. `status` is what separates the two, so a
    proposal is a real row that can be listed and approved rather than a
    message that has to be kept somewhere else.

    Note the id prefix is `S`, while a student's is `ST`. They cannot collide —
    `codes.number_in_code` matches the prefix exactly, so "ST_000001" is not a
    subject id — but `S_000001` and `ST_000001` do read alike to a person.
    """

    __tablename__ = "subjects"
    __table_args__ = (
        CheckConstraint(
            f"status IN ('{SUBJECT_PENDING}', '{SUBJECT_APPROVED}')",
            name="ck_subjects_status",
        ),
        # One "Mathematics" per school, however it was capitalised. Checked in
        # the router first for a readable message; this is what holds when two
        # teachers propose the same subject at the same moment.
        Index("uq_subjects_name", func.lower(text("name")), unique=True),
    )

    subject_id: Mapped[str] = mapped_column(String(16), primary_key=True)
    uuid: Mapped[uuid_lib.UUID] = mapped_column(
        Uuid, unique=True, default=_new_uuid
    )
    name: Mapped[str] = mapped_column(String(80))

    status: Mapped[str] = mapped_column(String(16), default=SUBJECT_APPROVED)

    # The teacher who proposed it, when one did. Null for a subject the
    # principal added directly.
    #
    # SET NULL rather than CASCADE — the only place in this schema that is not
    # a cascade. A teacher leaving the school must not take the school's
    # subject list with them; "who proposed Mathematics" is history, and losing
    # the answer is much better than losing the subject.
    proposed_by_teacher_id: Mapped[str | None] = mapped_column(
        ForeignKey("teachers.teacher_id", ondelete="SET NULL"), default=None
    )

    # Which principal approved it, and when. Null while pending.
    approved_by_user_id: Mapped[str | None] = mapped_column(
        ForeignKey("users.user_id", ondelete="SET NULL"), default=None
    )
    approved_at: Mapped[datetime | None] = mapped_column(DateTime, default=None)

    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class Attendance(Base):
    """One student, one day, present or absent.

    Keyed on an integer rather than a readable code: nobody quotes an
    attendance row the way they quote a student id, and there is one per pupil
    per school day — the counter table would be doing a lot of work for an id
    no one ever reads.

    `(student_id, date)` is unique, so a class cannot end up with two
    contradicting marks for the same child on the same day. Re-marking is an
    update, because a teacher correcting a mistake is the normal case, not an
    error.

    `class_id` is stored even though a student already has one. It records the
    class the mark was taken in, so moving a pupil to another class later
    cannot silently rewrite where they were last term.

    `teacher_id` is who took it — SET NULL rather than CASCADE for the same
    reason as Subject.proposed_by_teacher_id: a teacher leaving must not delete
    the school's attendance history.
    """

    __tablename__ = "attendance"
    __table_args__ = (
        CheckConstraint(
            f"status IN ('{ATTENDANCE_PRESENT}', '{ATTENDANCE_ABSENT}')",
            name="ck_attendance_status",
        ),
        Index("uq_attendance_student_date", "student_id", "date", unique=True),
    )

    id: Mapped[int] = mapped_column(primary_key=True)

    student_id: Mapped[str] = mapped_column(
        ForeignKey("students.student_id", ondelete="CASCADE"), index=True
    )
    class_id: Mapped[str] = mapped_column(
        ForeignKey("classes.class_id", ondelete="CASCADE"), index=True
    )
    teacher_id: Mapped[str | None] = mapped_column(
        ForeignKey("teachers.teacher_id", ondelete="SET NULL"), default=None
    )

    date: Mapped[date] = mapped_column(Date, index=True)
    status: Mapped[str] = mapped_column(String(1))

    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class TeacherSubject(Base):
    """Which subjects a teacher teaches. Many-to-many.

    A join table rather than a column on either side: a teacher teaches several
    subjects and a subject is taught by several teachers, and neither list has
    a sensible maximum to spread across columns.

    The primary key is the pair, so the same subject cannot be assigned to the
    same teacher twice — there is no meaningful difference between doing it
    once and doing it twice, and a duplicate would show up as a repeated row on
    their profile.

    Assignment is the principal's act, and `assigned_by_user_id` records whose.
    SET NULL there so the assignment outlives the principal who made it.
    """

    __tablename__ = "teacher_subjects"

    teacher_id: Mapped[str] = mapped_column(
        ForeignKey("teachers.teacher_id", ondelete="CASCADE"), primary_key=True
    )
    subject_id: Mapped[str] = mapped_column(
        ForeignKey("subjects.subject_id", ondelete="CASCADE"), primary_key=True
    )

    assigned_by_user_id: Mapped[str | None] = mapped_column(
        ForeignKey("users.user_id", ondelete="SET NULL"), default=None
    )
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class TeacherExperience(Base):
    """One previous post on a teacher's record: school, address, years there.

    Its own table because "work experience" is a list — a teacher who taught at
    three schools has three of these, and three sets of columns on `teachers`
    would cap it at three and leave two empty for most people.

    Keyed on an integer: a row here is a line on a CV, not something anyone
    quotes by id.

    `years` is numeric with one decimal place, so "2.5 years" is storable. An
    integer would have quietly rounded half a school year away, and that is
    exactly the sort of detail someone put on a form on purpose.
    """

    __tablename__ = "teacher_experience"

    id: Mapped[int] = mapped_column(primary_key=True)
    teacher_id: Mapped[str] = mapped_column(
        ForeignKey("teachers.teacher_id", ondelete="CASCADE"), index=True
    )

    school_name: Mapped[str] = mapped_column(String(160))
    school_address: Mapped[str] = mapped_column(String(500), default="")
    years: Mapped[Decimal] = mapped_column(Numeric(4, 1))

    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)
