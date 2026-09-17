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
    ROLE_TEACHER,
    SchoolClass,
    Teacher,
    User,
)


def is_principal(user: User) -> bool:
    return user.role == ROLE_PRINCIPAL


def require_teacher(db: Session, user: User) -> Teacher:
    """The teacher profile behind this request — for anything needing an owner.

    A class belongs to a teacher, so creating, renaming or deleting one is a
    teacher's act. The principal is refused here on purpose and told why: they
    see everything (see [reader_scope]) but own nothing.
    """
    if is_principal(user):
        raise HTTPException(
            status.HTTP_403_FORBIDDEN,
            detail=(
                "A class is created and edited by the teacher who owns it. "
                "A principal can see every class but does not own one."
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


def require_staff(db: Session, user: User) -> Teacher | None:
    """A teacher or the principal, returning the teacher row if there is one.

    For the things both roles do. A student-portal account is refused.
    """
    if is_principal(user):
        return None
    return require_teacher(db, user)


def reader_scope(db: Session, user: User) -> Teacher | None:
    """Who this request may *read*, as a scope.

    The teacher to filter by, or None meaning school-wide — which is the
    principal, whose whole job needs every class and every student.
    """
    if is_principal(user):
        return None
    return require_teacher(db, user)


def owned_class(db: Session, teacher: Teacher, class_id: str) -> SchoolClass:
    """The class, if it belongs to this teacher.

    Someone else's class is reported as missing rather than forbidden, so the
    endpoint cannot be used to discover which ids exist.
    """
    school_class = db.scalar(
        select(SchoolClass).where(
            SchoolClass.class_id == class_id,
            SchoolClass.teacher_id == teacher.teacher_id,
        )
    )
    if school_class is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Class not found")
    return school_class


def readable_class(db: Session, user: User, class_id: str) -> SchoolClass:
    """One class, if this user may see it.

    A teacher's own, or any class at all for the principal.
    """
    teacher = reader_scope(db, user)

    if teacher is None:
        school_class = db.get(SchoolClass, class_id)
        if school_class is None:
            raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Class not found")
        return school_class

    return owned_class(db, teacher, class_id)
