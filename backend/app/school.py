"""The four changes to a school's classes and pupils, and the rules on them.

Creating a class, deleting one, registering a pupil and removing one. These
lived in the classes router until 2026-09-20, when they gained a second
caller: a teacher's request for one of them is granted later, by a principal,
through [app.approvals] — and the change that happens then has to be the same
change, down to the duplicate checks.

That is the reason this module exists. The alternative was the approval path
re-implementing "add a class", and the two drifting until an approved request
did something the direct call would have refused.

**Everything here validates as if the request were brand new.** A class name
that was free when a teacher asked for it may have been taken by the time the
principal grants it; a pupil may already have been registered by someone else.
So the checks run at execution time, not at request time — and a rejection
then is a normal outcome, not a bug.

Nothing here commits, except where a commit is the only way to turn a unique
index into a readable message ([commit_or_409]). Callers own the transaction.
"""

from fastapi import HTTPException, status
from sqlalchemy import delete, func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app import codes, student_mapping
from app.database import class_roster
from app.models import (
    Attendance,
    SchoolClass,
    Student,
    StudentMapping,
    Teacher,
    User,
)
from app.schemas import (
    ClassCreateRequest,
    ClassOut,
    StudentCreateRequest,
    StudentDetails,
    StudentOut,
)

# The fields the duplicate rule compares, besides the class. Twins share all of
# these but the name, which is why the name is in the list: two children with
# the same everything except the name are two children.
_SAME_CHILD_TEXT = ("name", "address", "mother_name", "father_name")
_SAME_CHILD_EXACT = (
    "date_of_birth",
    "mother_email",
    "father_email",
    "mother_mobile",
    "father_mobile",
)


def commit_or_409(db: Session, message: str) -> None:
    """Commits, turning a unique-index refusal into a readable 409.

    The callers check for duplicates before writing, so this only fires when
    two devices write the same thing at the same moment and both pass the
    check.
    """
    try:
        db.commit()
    except IntegrityError as error:
        db.rollback()
        raise HTTPException(status.HTTP_409_CONFLICT, detail=message) from error


# --- Reading back -------------------------------------------------------------


def classes_out(db: Session, *conditions) -> list[ClassOut]:
    """Classes with the name of the teacher who owns each.

    The name is joined in for the principal's dashboard, which lists every
    class in the school: two teachers each having a "Nursery" is normal, so a
    flat list without the owner's name would be actively misleading. A teacher
    reading their own list just sees their own name, which costs nothing.

    An **outer** join since 0006. A class with no teacher is a class the
    principal has created and not yet handed on; an inner join would have made
    it vanish from the very list it was created to appear in — a class that
    exists, that nobody can see, and that still blocks its own name.
    """
    rows = db.execute(
        select(SchoolClass, User.full_name)
        .outerjoin(Teacher, Teacher.teacher_id == SchoolClass.teacher_id)
        .outerjoin(User, User.user_id == Teacher.user_id)
        .where(*conditions)
        # Creation order, which is the order the dashboard has always listed
        # them.
        .order_by(SchoolClass.class_id)
    ).all()

    columns = [column.key for column in SchoolClass.__table__.columns]
    return [
        ClassOut.model_validate(
            {key: getattr(school_class, key) for key in columns}
            | {"teacher_name": teacher_name}
        )
        for school_class, teacher_name in rows
    ]


def students_out(db: Session, *conditions) -> list[StudentOut]:
    """Students with their roll numbers, which come from the class_roster view."""
    rows = db.execute(
        select(Student, class_roster.c.roll_number)
        .join(class_roster, class_roster.c.student_id == Student.student_id)
        .where(*conditions)
        .order_by(Student.class_id, class_roster.c.roll_number)
    ).all()

    columns = [column.key for column in Student.__table__.columns]
    return [
        StudentOut.model_validate(
            {key: getattr(student, key) for key in columns}
            | {"roll_number": roll}
        )
        for student, roll in rows
    ]


# --- Classes ------------------------------------------------------------------


def reject_duplicate_class_name(
    db: Session,
    teacher_id: str | None,
    name: str,
    ignore_id: str | None = None,
) -> None:
    """Case-insensitive, like the app's check: "nursery" and "Nursery" are the
    same tile. The app checks too, but only against its own copy of the list —
    two devices adding the same name at once would both pass that.

    Scoped to one teacher, including the **unassigned** pseudo-teacher: a null
    `teacher_id` is compared with `IS NULL`, so the principal cannot create
    two unassigned "Nursery" classes either. `=` against NULL is never true in
    SQL, which would have let exactly that through.
    """
    owner = (
        SchoolClass.teacher_id.is_(None)
        if teacher_id is None
        else SchoolClass.teacher_id == teacher_id
    )
    query = select(SchoolClass.class_id).where(
        owner, func.lower(SchoolClass.name) == func.lower(name)
    )
    if ignore_id is not None:
        query = query.where(SchoolClass.class_id != ignore_id)

    if db.scalar(query) is not None:
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            detail=f'A class called "{name}" already exists',
        )


def create_class(
    db: Session, *, teacher_id: str | None, payload: ClassCreateRequest
) -> SchoolClass:
    """Adds a class — and, when restoring from a class file, its students.

    One request and one transaction for both: if a restore were a class create
    followed by student creates, a dropped connection between them would leave
    an empty class on every device and the students nowhere.

    Flushed, not committed. The caller commits, because the approval path has
    a request to mark decided in the same transaction — and a class that
    exists while the request that created it still reads "pending" is a state
    nobody can explain.
    """
    reject_duplicate_class_name(db, teacher_id, payload.name)

    school_class = SchoolClass(
        class_id=codes.next_code(db, codes.CLASS),
        teacher_id=teacher_id,
        name=payload.name,
        color_slot=payload.color_slot,
    )
    db.add(school_class)
    db.flush()

    restored: list[Student] = []
    for archived in payload.students:
        student_id = archived.student_id
        is_ours = (
            student_id is not None
            and codes.number_in_code(student_id, codes.STUDENT) is not None
        )

        if not is_ours:
            # Missing, or from a file this server never issued — a fresh id.
            student_id = codes.next_code(db, codes.STUDENT)
        elif db.get(Student, student_id) is not None:
            # Refused rather than renumbered: the id is what paper registers
            # were written against, and quietly changing it would break that
            # link. Almost always the same file restored twice.
            db.rollback()
            raise HTTPException(
                status.HTTP_409_CONFLICT,
                detail=(
                    f"Student {student_id} is already registered. This class "
                    "file may have been restored before."
                ),
            )
        else:
            codes.reserve_code(db, codes.STUDENT, student_id)

        student = Student(
            student_id=student_id,
            class_id=school_class.class_id,
            **archived.model_dump(exclude={"student_id"}),
        )
        db.add(student)
        restored.append(student)

    if restored:
        try:
            db.flush()
        except IntegrityError as error:
            db.rollback()
            raise HTTPException(
                status.HTTP_409_CONFLICT,
                detail="The class file lists the same child twice",
            ) from error
        # A restored pupil's parents may already have accounts.
        for student in restored:
            student_mapping.sync_student(db, student)

    return school_class


def delete_class(db: Session, school_class: SchoolClass) -> None:
    """Removes a class and every student in it.

    The students are deleted explicitly rather than left to ON DELETE CASCADE.
    PostgreSQL would honour the cascade, but SQLite — which the test suite
    runs on — ignores foreign key actions unless every connection turns them
    on, and relying on it there would leave the students behind as orphans
    nothing lists.
    """
    db.execute(
        delete(StudentMapping).where(
            StudentMapping.student_id.in_(
                select(Student.student_id).where(
                    Student.class_id == school_class.class_id
                )
            )
        )
    )
    db.execute(delete(Student).where(Student.class_id == school_class.class_id))
    db.delete(school_class)


# --- Students -----------------------------------------------------------------


def same_child(
    db: Session,
    class_id: str,
    details: StudentDetails,
    *,
    excluding: str | None = None,
) -> Student | None:
    """A student already in [class_id] who is this child, by the duplicate rule.

    Compared in SQL with lower() on both sides, so the comparison is exactly
    the one the unique index enforces — Python's and the database's idea of
    lower case can differ outside plain English letters.

    [excluding] is the pupil being edited, who always matches themselves.
    """
    conditions = [Student.class_id == class_id]
    if excluding is not None:
        conditions.append(Student.student_id != excluding)
    for field in _SAME_CHILD_TEXT:
        conditions.append(
            func.lower(getattr(Student, field))
            == func.lower(getattr(details, field))
        )
    for field in _SAME_CHILD_EXACT:
        conditions.append(getattr(Student, field) == getattr(details, field))
    return db.scalar(select(Student).where(*conditions))


def reject_duplicate_child(
    db: Session,
    school_class: SchoolClass,
    payload: StudentDetails,
    *,
    excluding: str | None = None,
) -> None:
    existing = same_child(
        db, school_class.class_id, payload, excluding=excluding
    )
    if existing is None:
        return

    raise HTTPException(
        status.HTTP_409_CONFLICT,
        detail=(
            f"{existing.name} is already registered in {school_class.name} "
            f"as {existing.student_id}, with the same date of birth, "
            "address, and parents' details"
        ),
    )


def create_student(
    db: Session, *, school_class: SchoolClass, payload: StudentCreateRequest
) -> Student:
    """Registers a pupil into a class. Flushed, not committed."""
    reject_duplicate_child(db, school_class, payload)

    student = Student(
        student_id=codes.next_code(db, codes.STUDENT),
        **payload.model_dump(),
    )
    db.add(student)
    db.flush()
    # Case 1: parents who already have accounts are mapped straight away.
    student_mapping.sync_student(db, student)
    return student


def update_student(
    db: Session,
    *,
    student: Student,
    school_class: SchoolClass,
    payload: StudentDetails,
) -> None:
    """Replaces a pupil's details. Flushed, not committed.

    The whole record, not a difference — the edit form sends every field, and
    a field it left out would otherwise keep a value the teacher had cleared.
    The class is not among them: moving a pupil is a different act.
    """
    reject_duplicate_child(
        db, school_class, payload, excluding=student.student_id
    )
    for field, value in payload.model_dump().items():
        setattr(student, field, value)
    db.flush()
    # A changed number maps the account it belongs to, and unmaps the one it
    # used to.
    student_mapping.sync_student(db, student)


def delete_student(db: Session, student: Student) -> None:
    """Removes one pupil, with their attendance and their guardian links.

    Their marks go because a register naming a pupil who is registered nowhere
    is a row nothing can render. Their guardian links go so a parent account
    linked only to this child falls back to "no children linked yet" rather
    than pointing at a pupil who has gone.

    Deleted here rather than left to ON DELETE CASCADE, for the same reason
    [delete_class] does it: PostgreSQL would honour the cascade, SQLite —
    which the test suite runs on — ignores foreign key actions unless every
    connection enables them, so the orphans would only ever show up in
    production.
    """
    db.execute(
        delete(Attendance).where(Attendance.student_id == student.student_id)
    )
    db.execute(
        delete(StudentMapping).where(
            StudentMapping.student_id == student.student_id
        )
    )
    db.delete(student)
