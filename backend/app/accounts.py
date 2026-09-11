"""Creating users and their teacher profiles, shared by the auth and classes
routers so the id rules live in one place."""

from sqlalchemy import select
from sqlalchemy.orm import Session

from app import codes
from app.models import ROLE_TEACHER, Teacher, User


def new_user(db: Session, **fields) -> User:
    """A user with the next U_ id, added to the session but not committed."""
    user = User(user_id=codes.next_code(db, codes.USER), **fields)
    db.add(user)
    return user


def ensure_teacher(db: Session, user: User) -> Teacher:
    """The TR_ profile for a user whose role is teacher, created on first need.

    Called when a user becomes a teacher — at sign-up or on the profile screen —
    and again by the classes router, so a teacher whose profile is somehow
    missing gets one rather than a confusing error.
    """
    teacher = db.scalar(select(Teacher).where(Teacher.user_id == user.user_id))
    if teacher is None:
        teacher = Teacher(
            teacher_id=codes.next_code(db, codes.TEACHER), user_id=user.user_id
        )
        db.add(teacher)
        db.flush()
    return teacher


def apply_role(db: Session, user: User, role: str) -> None:
    user.role = role
    if role == ROLE_TEACHER:
        # Flushed first so the user row exists for the teacher's foreign key.
        db.flush()
        ensure_teacher(db, user)
