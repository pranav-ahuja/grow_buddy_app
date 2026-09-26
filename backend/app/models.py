import uuid as uuid_lib
from datetime import date, datetime, time
from decimal import Decimal

from sqlalchemy import (
    JSON,
    Boolean,
    CheckConstraint,
    Date,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    Numeric,
    String,
    Time,
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
    """A class on a dashboard. CL_000001.

    **`teacher_id` is the class teacher — the one owner — and it is nullable.**
    The principal creates classes now, and a class created in August before
    anyone has been given it is a real thing with nobody teaching it yet. Null
    means exactly that: unassigned, not broken.

    A class may be taught by **more than one** teacher. The extra ones live in
    `class_teachers`; this column holds the first among them. One owner plus a
    set, rather than the set alone, so `uq_classes_teacher_name` still means
    what it always did — two teachers each having a "Nursery" is normal, and
    neither should see the other's.

    Ask [app.access.teacher_class_ids] for "which classes are mine": it
    answers with both halves, and no router should ask with a bare
    `teacher_id ==` again.

    The roll numbers and student names that sit alongside a class are in the
    `class_roster` view (see app/database.py), not here — a class has to exist
    before its first student can be registered into it. Note the view's
    `teacher_id` is this column, so it names the owner and knows nothing of
    co-teachers; it is not a scope to filter by any more.
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
    # Nullable since 0006: an unassigned class is one the principal has
    # created and not yet handed to anyone. CASCADE still, so deleting a
    # teacher takes the classes that were theirs alone with them.
    teacher_id: Mapped[str | None] = mapped_column(
        ForeignKey("teachers.teacher_id", ondelete="CASCADE"),
        index=True,
        default=None,
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


class StudentGuardian(Base):
    """Which account may see which pupil — the parent's link to their child.

    The app is for parents, so a "student" account is really a parent
    operating on a child's behalf. Nothing joined the two before this: a
    `students` row is created by a teacher from a paper form, and a
    `users` row with role 'student' was just a role. Without this table a
    parent who signs up cannot be shown anything at all.

    **Many-to-many, deliberately.** A parent may have two children at the
    school, and a child may have two parents who each want the app. Either as
    a column would have capped the wrong side of that.

    **Only staff create these rows.** A parent cannot claim a child by
    asserting they are the parent — that is the one thing in this schema where
    getting it wrong hands a stranger a child's address, attendance and
    contacts. The teacher who registered the pupil, or the principal, makes
    the link; the register-student form already collected the parents' names
    and numbers, so the school is the party that actually knows.

    A self-service claim ("my number is on that child's record, link me") is
    the obvious convenience and is deliberately absent: it needs an approval
    step, which is phase 5.

    `linked_by_user_id` records who made the link, SET NULL so the link
    outlives the staff member who made it.
    """

    __tablename__ = "student_guardians"

    user_id: Mapped[str] = mapped_column(
        ForeignKey("users.user_id", ondelete="CASCADE"), primary_key=True
    )
    # Indexed as well as being half the primary key: that key leads on
    # `user_id`, so it answers "which children may this account see" but not
    # "who are this pupil's guardians" — which is what the staff-facing list
    # and every future notification fan-out will ask.
    student_id: Mapped[str] = mapped_column(
        ForeignKey("students.student_id", ondelete="CASCADE"),
        primary_key=True,
        index=True,
    )

    # "Mother", "Father", "Grandmother" — free text, as on the student's own
    # guardian block. Blank when nobody said.
    relation: Mapped[str] = mapped_column(String(32), default="")

    linked_by_user_id: Mapped[str | None] = mapped_column(
        ForeignKey("users.user_id", ondelete="SET NULL"), default=None
    )
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class ClassTeacher(Base):
    """An extra teacher on a class — the co-teachers, beside the owner.

    A class has one class teacher (`classes.teacher_id`) and may have any
    number of others: a nursery with a second adult in the room, a subject
    teacher who takes the same group. The principal picks them, several at a
    time, from the class screen.

    Many-to-many and keyed on the pair, so the same teacher cannot be added to
    a class twice — which is what lets the picker send the whole set without
    first working out the difference.

    **The owner is not repeated here.** One fact, one place: a teacher in both
    would be a teacher who could be removed from a class and still be
    teaching it. [app.access.teacher_class_ids] unions the two halves, and it
    is the only thing that should.

    `assigned_by_user_id` is SET NULL, like every other "who did this" column
    in this schema: a principal leaving must not delete the school's teaching
    assignments on their way out.
    """

    __tablename__ = "class_teachers"

    class_id: Mapped[str] = mapped_column(
        ForeignKey("classes.class_id", ondelete="CASCADE"), primary_key=True
    )
    # Indexed as well as being half the key: the key leads on class_id, so it
    # answers "who teaches this class" but not "which classes does this
    # teacher take" — which is the question every dashboard load asks.
    teacher_id: Mapped[str] = mapped_column(
        ForeignKey("teachers.teacher_id", ondelete="CASCADE"),
        primary_key=True,
        index=True,
    )

    assigned_by_user_id: Mapped[str | None] = mapped_column(
        ForeignKey("users.user_id", ondelete="SET NULL"), default=None
    )
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


# What a teacher can ask the principal for. Each one is an act the principal
# may simply do and a teacher may only request — that asymmetry is the whole
# point of the table.
REQUEST_CLASS_CREATE = "class_create"
REQUEST_CLASS_DELETE = "class_delete"
REQUEST_STUDENT_ADD = "student_add"
REQUEST_STUDENT_REMOVE = "student_remove"

REQUEST_KINDS = (
    REQUEST_CLASS_CREATE,
    REQUEST_CLASS_DELETE,
    REQUEST_STUDENT_ADD,
    REQUEST_STUDENT_REMOVE,
)

REQUEST_PENDING = "pending"
REQUEST_APPROVED = "approved"
REQUEST_REJECTED = "rejected"

REQUEST_STATUSES = (REQUEST_PENDING, REQUEST_APPROVED, REQUEST_REJECTED)

_KIND_LIST = "', '".join(REQUEST_KINDS)
_STATUS_LIST = "', '".join(REQUEST_STATUSES)


class ChangeRequest(Base):
    """A teacher asking the principal to make a change, and the answer.

    Creating a class, deleting one, registering a pupil and removing one are
    all things the principal does outright. A teacher may only ask: the row
    below *is* the asking, and until somebody approves it **nothing else in
    the database has changed**. That is the rule to hold on to — the class
    does not exist yet, the pupil is not registered yet, and no count, roster
    or register includes them. A pending row that had already half happened
    would be the worst of both.

    `payload` carries what to do on approval — the class name and colour, or
    the whole register-student form — because by then the teacher may be
    offline, or gone. It is the request's own copy, and it is validated again
    when it runs: a class name that was free when it was asked for may have
    been taken by the time it is granted.

    `requested_by_name` is deliberately **denormalised**. The teacher link is
    SET NULL so a teacher leaving does not erase the school's decision
    history, and a queue reading "somebody wanted this class deleted" is not a
    queue anyone can act on.

    An integer key, not an `RQ_` code: nobody quotes a request. It is read off
    a list, decided, and done with — the same reasoning as `attendance`.
    """

    __tablename__ = "change_requests"
    __table_args__ = (
        CheckConstraint(
            f"kind IN ('{_KIND_LIST}')", name="ck_change_requests_kind"
        ),
        CheckConstraint(
            f"status IN ('{_STATUS_LIST}')", name="ck_change_requests_status"
        ),
    )

    id: Mapped[int] = mapped_column(
        Integer, primary_key=True, autoincrement=True
    )
    uuid: Mapped[uuid_lib.UUID] = mapped_column(
        Uuid, unique=True, default=_new_uuid
    )

    kind: Mapped[str] = mapped_column(String(32))
    # Indexed because the principal's queue is "pending, newest first", by
    # far the most frequent read of this table.
    status: Mapped[str] = mapped_column(
        String(16), default=REQUEST_PENDING, index=True
    )

    requested_by_teacher_id: Mapped[str | None] = mapped_column(
        ForeignKey("teachers.teacher_id", ondelete="SET NULL"),
        index=True,
        default=None,
    )
    requested_by_name: Mapped[str] = mapped_column(String(120), default="")

    # The target, where there already is one. Null on a class_create, whose
    # class does not exist until the request is granted.
    class_id: Mapped[str | None] = mapped_column(
        ForeignKey("classes.class_id", ondelete="SET NULL"), default=None
    )
    student_id: Mapped[str | None] = mapped_column(
        ForeignKey("students.student_id", ondelete="SET NULL"), default=None
    )

    # One line the principal can decide from without opening anything:
    # 'Delete "Nursery" and its 12 students'. Written when the request is
    # raised, so it still describes what was asked even after the class it
    # names has gone.
    summary: Mapped[str] = mapped_column(String(300), default="")

    # What to do on approval. JSON on both engines — JSONB on PostgreSQL,
    # TEXT on SQLite — because the shape differs per kind, and a column per
    # field would be four half-empty sets of them.
    payload: Mapped[dict] = mapped_column(JSON, default=dict)

    decided_by_user_id: Mapped[str | None] = mapped_column(
        ForeignKey("users.user_id", ondelete="SET NULL"), default=None
    )
    decided_at: Mapped[datetime | None] = mapped_column(DateTime, default=None)
    # Why it was turned down, in the principal's words. Shown to the teacher,
    # because "rejected" with no reason is how a teacher asks again tomorrow.
    decision_note: Mapped[str] = mapped_column(String(500), default="")

    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


# Who a notification is for: one named account, or everybody.
NOTIFY_AUDIENCE_USER = "user"
NOTIFY_AUDIENCE_BROADCAST = "broadcast"

NOTIFY_AUDIENCES = (NOTIFY_AUDIENCE_USER, NOTIFY_AUDIENCE_BROADCAST)

_AUDIENCE_LIST = "', '".join(NOTIFY_AUDIENCES)


class Notification(Base):
    """One line in somebody's notification tab.

    The fields are the ones asked for: the **date** and the **time** it was
    raised, its **source**, whether it is for an **individual account or a
    broadcast**, and the **message** itself as text.

    Date and time are two columns rather than one timestamp because that is
    how the tab reads them — grouped under "20 September", each line stamped
    "14:32". `created_at` is kept alongside for ordering, which is the one job
    a split date and time do badly.

    **The message is stored, not generated at read time.** "Asha Rao requests
    approval for removal of Nursery" has to still say that in a month, after
    Nursery is gone and Asha has left. A notification that re-renders itself
    from live rows quietly rewrites history — and the history is the only
    reason to keep it.

    `request_id` is what makes the tab actionable: where it is set, the line
    is an approval the principal can decide on the spot. Null for anything
    that is only news.
    """

    __tablename__ = "notifications"
    __table_args__ = (
        CheckConstraint(
            f"audience IN ('{_AUDIENCE_LIST}')",
            name="ck_notifications_audience",
        ),
        # A 'user' notice with nobody to deliver it to, and a broadcast
        # addressed to one person, are both nonsense the table should not be
        # able to hold.
        CheckConstraint(
            f"(audience = '{NOTIFY_AUDIENCE_USER}' AND user_id IS NOT NULL) "
            f"OR (audience = '{NOTIFY_AUDIENCE_BROADCAST}' "
            "AND user_id IS NULL)",
            name="ck_notifications_addressed",
        ),
    )

    id: Mapped[int] = mapped_column(
        Integer, primary_key=True, autoincrement=True
    )
    uuid: Mapped[uuid_lib.UUID] = mapped_column(
        Uuid, unique=True, default=_new_uuid
    )

    date: Mapped[date] = mapped_column(Date)
    time: Mapped[time] = mapped_column(Time)

    # Where it came from, in words: a teacher's name, or "GrowBuddy" for
    # anything the system says itself. Text rather than a user link, because
    # the source of a notice outlives the account that caused it, and some
    # notices have no account behind them at all.
    source: Mapped[str] = mapped_column(String(120), default="GrowBuddy")

    audience: Mapped[str] = mapped_column(
        String(16), default=NOTIFY_AUDIENCE_USER
    )
    # The recipient, for an individual notice. Null on a broadcast, which
    # everybody reads. CASCADE: a deleted account's notices go with it.
    user_id: Mapped[str | None] = mapped_column(
        ForeignKey("users.user_id", ondelete="CASCADE"),
        index=True,
        default=None,
    )

    message: Mapped[str] = mapped_column(String(500))

    # Set where this line is an approval to decide. SET NULL rather than
    # CASCADE: the notice that something was asked for is still true after
    # the request itself has been cleared away.
    request_id: Mapped[int | None] = mapped_column(
        ForeignKey("change_requests.id", ondelete="SET NULL"), default=None
    )

    # Per recipient, which is why it lives here and not on the request: two
    # principals each get their own row and each reads it in their own time.
    read_at: Mapped[datetime | None] = mapped_column(DateTime, default=None)

    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


# Which contact a pending change is for. The channel is stored rather than
# inferred from the value's shape: "does it contain an @" is a guess, and a
# guess is how a phone code ends up redeemed against an email address.
CONTACT_CHANNEL_PHONE = "phone"
CONTACT_CHANNEL_EMAIL = "email"

CONTACT_CHANNELS = (CONTACT_CHANNEL_PHONE, CONTACT_CHANNEL_EMAIL)

_CONTACT_CHANNEL_LIST = "', '".join(CONTACT_CHANNELS)


class ContactChangeCode(Base):
    """A one-time code proving somebody owns the email or number they are
    moving their own account to.

    **Its own table, for the reason PasswordResetCode gives.** An `OtpCode` is
    redeemable for a full login token, and `/auth/otp/verify` finds the account
    *by the number in the request* — so a code issued to prove a new number
    could otherwise be spent creating a second account for it, or logging into
    the account of whoever already holds it. This one is keyed by `user_id`,
    carries the value it was issued for, and can do exactly one thing: move
    that contact onto that user.

    **The new value lives here, not on `users`.** It is what the signed-in user
    typed, and it is not a fact about them until a code sent to it comes back.
    Writing it to `users.phone` first and marking it unverified would make the
    unproven number the one they have to log in with — which is how a typo
    locks somebody out of an account they can still see on screen. So the
    column on `users` does not move until `consumed_at` is set here.

    `attempts` and `expires_at` do the same job, under the same settings, as
    they do on an OtpCode: a code is guessable in six digits, so it has to run
    out of both time and tries.
    """

    __tablename__ = "contact_change_codes"
    __table_args__ = (
        CheckConstraint(
            f"channel IN ('{_CONTACT_CHANNEL_LIST}')",
            name="ck_contact_change_codes_channel",
        ),
        # The lookup every request and verify does: this user's outstanding code
        # for this channel, newest first.
        Index(
            "ix_contact_change_codes_user_channel",
            "user_id",
            "channel",
            "consumed_at",
        ),
    )

    id: Mapped[int] = mapped_column(primary_key=True)

    # CASCADE, like every other row hanging off an account: a deleted user's
    # half-finished contact change has nothing left to be about.
    user_id: Mapped[str] = mapped_column(
        ForeignKey("users.user_id", ondelete="CASCADE"), index=True
    )

    channel: Mapped[str] = mapped_column(String(16))

    # Normalised on the way in — a phone through normalize_phone, an email
    # lower-cased — so what is committed to `users` is what a later login will
    # be looked up by. Stored wide enough for an email, which is the longer of
    # the two.
    new_value: Mapped[str] = mapped_column(String(255))

    code_hash: Mapped[str] = mapped_column(String(255))
    expires_at: Mapped[datetime] = mapped_column(DateTime)
    attempts: Mapped[int] = mapped_column(Integer, default=0)
    consumed_at: Mapped[datetime | None] = mapped_column(DateTime, default=None)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)

    def is_usable(self, now: datetime, max_attempts: int) -> bool:
        """Deliberately the same three conditions as OtpCode.is_usable.

        Kept as its own copy rather than shared through a mixin: the two tables
        are separate on purpose, and a shared base class is the seam along which
        "an OTP is an OTP" creeps back in.
        """
        return (
            self.consumed_at is None
            and self.expires_at > now
            and self.attempts < max_attempts
        )
