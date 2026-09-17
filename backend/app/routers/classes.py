from fastapi import APIRouter, HTTPException, Response, status
from sqlalchemy import delete, func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app import codes
from app.access import (
    owned_class,
    readable_class,
    reader_scope,
    require_teacher,
)
from app.database import class_roster
from app.deps import CurrentUser, DbSession
from app.models import (
    SchoolClass,
    Student,
    Teacher,
    User,
)
from app.schemas import (
    ClassCreateRequest,
    ClassOut,
    ClassUpdateRequest,
    RosterEntry,
    StudentCreateRequest,
    StudentDetails,
    StudentOut,
)

router = APIRouter(tags=["classes"])

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



def _reject_duplicate_name(
    db: Session, teacher: Teacher, name: str, ignore_id: str | None = None
) -> None:
    """Case-insensitive, like the app's check: "nursery" and "Nursery" are the
    same tile to a teacher. The app checks too, but only against its own copy
    of the list — two devices adding the same name at once would both pass
    that."""
    query = select(SchoolClass.class_id).where(
        SchoolClass.teacher_id == teacher.teacher_id,
        func.lower(SchoolClass.name) == func.lower(name),
    )
    if ignore_id is not None:
        query = query.where(SchoolClass.class_id != ignore_id)

    if db.scalar(query) is not None:
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            detail=f'A class called "{name}" already exists',
        )


def _same_child(db: Session, class_id: str, details: StudentDetails) -> Student | None:
    """A student already in [class_id] who is this child, by the duplicate rule.

    Compared in SQL with lower() on both sides, so the comparison is exactly
    the one the unique index enforces — Python's and the database's idea of
    lower case can differ outside plain English letters.
    """
    conditions = [Student.class_id == class_id]
    for field in _SAME_CHILD_TEXT:
        conditions.append(
            func.lower(getattr(Student, field)) == func.lower(getattr(details, field))
        )
    for field in _SAME_CHILD_EXACT:
        conditions.append(getattr(Student, field) == getattr(details, field))
    return db.scalar(select(Student).where(*conditions))


def _students_out(db: Session, *conditions) -> list[StudentOut]:
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
            {key: getattr(student, key) for key in columns} | {"roll_number": roll}
        )
        for student, roll in rows
    ]


def _commit_or_409(db: Session, message: str) -> None:
    """Commits, turning a unique-index refusal into a readable 409.

    The routes check for duplicates before writing, so this only fires when two
    devices write the same thing at the same moment and both pass the check.
    """
    try:
        db.commit()
    except IntegrityError as error:
        db.rollback()
        raise HTTPException(status.HTTP_409_CONFLICT, detail=message) from error


# --- Classes -----------------------------------------------------------------


def _classes_out(db: Session, *conditions) -> list[ClassOut]:
    """Classes with the name of the teacher who owns each.

    The name is joined in for the principal's dashboard, which lists every
    class in the school: two teachers each having a "Nursery" is normal, so a
    flat list without the owner's name would be actively misleading. A teacher
    reading their own list just sees their own name, which costs nothing.
    """
    rows = db.execute(
        select(SchoolClass, User.full_name)
        .join(Teacher, Teacher.teacher_id == SchoolClass.teacher_id)
        .join(User, User.user_id == Teacher.user_id)
        .where(*conditions)
        # Creation order, which is the order the dashboard has always listed them.
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


@router.get("/classes", response_model=list[ClassOut])
def list_classes(user: CurrentUser, db: DbSession) -> list[ClassOut]:
    """A teacher's own classes — or, for the principal, every class there is."""
    teacher = reader_scope(db, user)

    if teacher is None:
        return _classes_out(db)
    return _classes_out(db, SchoolClass.teacher_id == teacher.teacher_id)


@router.post(
    "/classes", response_model=ClassOut, status_code=status.HTTP_201_CREATED
)
def create_class(
    payload: ClassCreateRequest, user: CurrentUser, db: DbSession
) -> SchoolClass:
    """Adds a class — and, when restoring from a class file, its students.

    One request and one transaction for both: if a restore were a class create
    followed by student creates, a dropped connection between them would leave
    an empty class on every device and the students nowhere.
    """
    teacher = require_teacher(db, user)
    _reject_duplicate_name(db, teacher, payload.name)

    school_class = SchoolClass(
        class_id=codes.next_code(db, codes.CLASS),
        teacher_id=teacher.teacher_id,
        name=payload.name,
        color_slot=payload.color_slot,
    )
    db.add(school_class)
    db.flush()

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

        db.add(
            Student(
                student_id=student_id,
                class_id=school_class.class_id,
                **archived.model_dump(exclude={"student_id"}),
            )
        )

    _commit_or_409(
        db,
        f'A class called "{payload.name}" already exists, or the class file '
        "lists the same student twice",
    )
    db.refresh(school_class)
    return school_class


@router.patch("/classes/{class_id}", response_model=ClassOut)
def update_class(
    class_id: str,
    payload: ClassUpdateRequest,
    user: CurrentUser,
    db: DbSession,
) -> SchoolClass:
    teacher = require_teacher(db, user)
    school_class = owned_class(db, teacher, class_id)

    if payload.name is not None:
        _reject_duplicate_name(db, teacher, payload.name, ignore_id=class_id)
        school_class.name = payload.name
    if payload.color_slot is not None:
        school_class.color_slot = payload.color_slot

    _commit_or_409(db, f'A class called "{payload.name}" already exists')
    db.refresh(school_class)
    return school_class


@router.delete("/classes/{class_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_class(class_id: str, user: CurrentUser, db: DbSession) -> Response:
    teacher = require_teacher(db, user)
    school_class = owned_class(db, teacher, class_id)

    # Explicit rather than left to ON DELETE CASCADE. PostgreSQL would honour
    # the cascade, but SQLite — which the test suite runs on — ignores foreign
    # key actions unless every connection turns them on, and relying on it
    # there would leave the students behind as orphans nothing lists.
    db.execute(delete(Student).where(Student.class_id == school_class.class_id))
    db.delete(school_class)
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/classes/{class_id}/roster", response_model=list[RosterEntry])
def class_roster_for(class_id: str, user: CurrentUser, db: DbSession) -> list:
    """The class as a table: class id, class name, roll number, student name."""
    readable_class(db, user, class_id)
    return list(
        db.execute(
            select(class_roster)
            .where(class_roster.c.class_id == class_id)
            .order_by(class_roster.c.roll_number)
        ).mappings()
    )


# --- Students ----------------------------------------------------------------


@router.get("/students", response_model=list[StudentOut])
def list_students(user: CurrentUser, db: DbSession) -> list[StudentOut]:
    # Every student at once rather than per class: the dashboard shows a count
    # on every tile, so it needs them all anyway, and one request beats nine.
    teacher = reader_scope(db, user)

    # The principal has access to every student in the school — one of the
    # things the role is for.
    if teacher is None:
        return _students_out(db)
    return _students_out(db, class_roster.c.teacher_id == teacher.teacher_id)


@router.post(
    "/students", response_model=StudentOut, status_code=status.HTTP_201_CREATED
)
def create_student(
    payload: StudentCreateRequest, user: CurrentUser, db: DbSession
) -> StudentOut:
    # Registering a student is one of the things the principal may do too, into
    # any class in the school; a teacher only into one of their own. A class id
    # from someone else's account is not a class this student can be filed
    # under.
    school_class = readable_class(db, user, payload.class_id)

    existing = _same_child(db, school_class.class_id, payload)
    if existing is not None:
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            detail=(
                f"{existing.name} is already registered in {school_class.name} "
                f"as {existing.student_id}, with the same date of birth, "
                "address, and parents' details"
            ),
        )

    student = Student(
        student_id=codes.next_code(db, codes.STUDENT),
        **payload.model_dump(),
    )
    db.add(student)
    _commit_or_409(
        db,
        f"{payload.name} is already registered in {school_class.name} with the "
        "same date of birth, address, and parents' details",
    )

    # Read back through the roster, which is where the roll number comes from.
    return _students_out(db, Student.student_id == student.student_id)[0]
