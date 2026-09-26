"""Who may do what, in one place.

These started as private helpers inside the classes router. Subjects and
attendance need the same questions answered — "is this a teacher?", "which
classes may they see?" — and three copies of a role check is how one of them
ends up subtly wider than the others. Rule changes land here now.

The shape to notice is [reader_scope]: it returns the teacher to filter a query
by, or **None meaning school-wide**. Deciding that once, by role, means a
caller cannot read across the whole school because it forgot to narrow — the
worst kind of bug to find in an app that holds children's records.
"""

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.accounts import ensure_teacher
from app.models import (
    ROLE_PRINCIPAL,
    ROLE_STUDENT,
    ROLE_TEACHER,
    ClassTeacher,
    SchoolClass,
    Student,
    StudentGuardian,
    Teacher,
    User,
)


def is_principal(user: User) -> bool:
    return user.role == ROLE_PRINCIPAL


def is_guardian(user: User) -> bool:
    """A 'student' account, which in practice is a parent using the app."""
    return user.role == ROLE_STUDENT


def guardian_student_ids(db: Session, user: User) -> set[str]:
    """The pupils this account is allowed to see. Empty until staff link it.

    Empty is the *correct* answer for a parent who has just signed up, not an
    error: nothing joins an account to a child until the school says so. The
    app shows "no children linked yet" rather than a failure, because the
    parent has done nothing wrong and there is nothing they can do about it
    themselves.
    """
    return set(
        db.scalars(
            select(StudentGuardian.student_id).where(
                StudentGuardian.user_id == user.user_id
            )
        )
    )


def guardian_class_ids(db: Session, user: User) -> set[str]:
    """The classes this account's children are in."""
    student_ids = guardian_student_ids(db, user)
    if not student_ids:
        return set()

    return set(
        db.scalars(
            select(Student.class_id).where(Student.student_id.in_(student_ids))
        )
    )


def require_teacher(db: Session, user: User) -> Teacher:
    """The `TR_` profile behind this request, for anything that needs one.

    A principal is refused, and the message says why: they have no teacher
    record at all, which is a different thing from being forbidden. They are
    not a member of staff who teaches, so there is no row to return.

    Note what this no longer means. Until 2026-09-20 it also read as "only a
    teacher may create or delete a class" — the principal is an admin now and
    does both. What is still true is the narrow thing: a principal has no
    `TR_` id, so anything that needs one cannot be done by them. Marking a
    register is the real example, and it is refused for its own reason —
    attendance is a first-hand observation.
    """
    if is_principal(user):
        raise HTTPException(
            status.HTTP_403_FORBIDDEN,
            detail=(
                "A principal has no teacher record, so this is a teacher's "
                "to do."
            ),
        )
    if user.role != ROLE_TEACHER:
        raise HTTPException(
            status.HTTP_403_FORBIDDEN, detail="Only teachers can manage classes"
        )
    return ensure_teacher(db, user)


def require_principal(user: User, *, action: str) -> None:
    """Refuses anyone but the principal.

    [action] completes the sentence the user reads, so the message says which
    thing they cannot do rather than a bare "forbidden".
    """
    if not is_principal(user):
        raise HTTPException(
            status.HTTP_403_FORBIDDEN,
            detail=f"Only the principal can {action}",
        )


def require_staff(
    db: Session, user: User, *, action: str | None = None
) -> Teacher | None:
    """A teacher or the principal, returning the teacher row if there is one.

    For the things both roles do. A parent's account is refused.

    [action] completes the refusal, because the default message comes from
    `require_teacher` and says "Only teachers can manage classes" — true on the
    classes routes it was written for, and actively misleading on, say, linking
    a parent to a pupil. A reader told the wrong reason goes looking in the
    wrong place.
    """
    if is_principal(user):
        return None

    if action is not None and is_guardian(user):
        raise HTTPException(
            status.HTTP_403_FORBIDDEN,
            detail=f"Only a teacher or the principal can {action}",
        )

    return require_teacher(db, user)


def reader_scope(db: Session, user: User) -> Teacher | None:
    """Who this request may *read*, as a scope.

    The teacher to filter by, or None meaning school-wide — which is the
    principal, whose whole job needs every class and every student.
    """
    if is_principal(user):
        return None
    return require_teacher(db, user)


def teacher_class_ids(db: Session, teacher: Teacher) -> set[str]:
    """Every class this teacher takes — the ones they own and the ones they
    were added to.

    **The one place that unions the two halves.** A class has one owner
    (`classes.teacher_id`) and any number of co-teachers (`class_teachers`),
    and a query that remembers only the first silently hides half a teacher's
    timetable. Nothing outside this module should write `teacher_id ==` about
    a class again.
    """
    owned = set(
        db.scalars(
            select(SchoolClass.class_id).where(
                SchoolClass.teacher_id == teacher.teacher_id
            )
        )
    )
    co_taught = set(
        db.scalars(
            select(ClassTeacher.class_id).where(
                ClassTeacher.teacher_id == teacher.teacher_id
            )
        )
    )
    return owned | co_taught


def taught_class(db: Session, teacher: Teacher, class_id: str) -> SchoolClass:
    """The class, if this teacher takes it — as owner or as a co-teacher.

    A class they do not take is reported as missing rather than forbidden, so
    the endpoint cannot be used to discover which ids exist.
    """
    if class_id not in teacher_class_ids(db, teacher):
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Class not found")

    school_class = db.get(SchoolClass, class_id)
    if school_class is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Class not found")
    return school_class


def owns_class(teacher: Teacher, school_class: SchoolClass) -> bool:
    """Whether this teacher is the **class teacher**, not merely one of them.

    Kept separate from [taught_class] because a few things are the owner's
    alone — renaming the class is the one that exists today. A co-teacher who
    could rename the class out from under its class teacher would be a
    surprise nobody asked for.
    """
    return school_class.teacher_id == teacher.teacher_id


def readable_class(db: Session, user: User, class_id: str) -> SchoolClass:
    """One class, if this user may see it.

    Three answers, by role: any class for the principal, their own for a
    teacher, and for a parent the classes their children are in.

    Always 404 rather than 403 for a class they may not see, so none of the
    three can use the endpoint to discover which ids exist.
    """
    if is_guardian(user):
        # Checked against the link table, not against the class: a parent's
        # access is "my child is in it", and the class itself says nothing
        # about that.
        if class_id not in guardian_class_ids(db, user):
            raise HTTPException(
                status.HTTP_404_NOT_FOUND, detail="Class not found"
            )
        school_class = db.get(SchoolClass, class_id)
        if school_class is None:
            raise HTTPException(
                status.HTTP_404_NOT_FOUND, detail="Class not found"
            )
        return school_class

    teacher = reader_scope(db, user)

    if teacher is None:
        school_class = db.get(SchoolClass, class_id)
        if school_class is None:
            raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Class not found")
        return school_class

    return taught_class(db, teacher, class_id)


def readable_student(db: Session, user: User, student_id: str) -> Student:
    """One pupil, if this user may see them.

    A parent reaches their own children directly; staff reach a pupil through
    the class, which is where their scope already lives.
    """
    student = db.get(Student, student_id)
    if student is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Student not found")

    if is_guardian(user):
        if student_id not in guardian_student_ids(db, user):
            raise HTTPException(
                status.HTTP_404_NOT_FOUND, detail="Student not found"
            )
        return student

    # Raises for a class this staff member may not see, which is the same
    # answer for the pupil in it.
    readable_class(db, user, student.class_id)
    return student
