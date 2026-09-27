"""Mapping parent accounts to pupils by the contacts on the pupil's record.

The mother's and father's mobile numbers and emails a teacher types into the
register-student form are the ones the parents log in with. An account whose
**verified** phone or email equals one of them is mapped to that pupil in
`student_mapping`, as Mother or Father:

- **Case 1**, the account existed first: [sync_student] runs when the pupil is
  registered or edited, and finds the accounts.
- **Case 2**, the pupil existed first: [sync_user] runs when an account signs
  up, proves a contact, or picks the student role, and finds the pupils.

Both run the same rule, so it does not matter which side came first. A mother
and a father each keep their own account; each is matched to the same pupils.

**Verified only.** A code has to have reached the number (phone + OTP login,
or a confirmed contact change), or Google — or a confirmed change — has to
vouch for the address. Otherwise anyone could sign up with a mother's number
and read her child's record.

Automatic rows (`source = contact_match`) are recomputed each time: one whose
numbers no longer match is removed, so correcting a mistyped number on the
record takes the child away from whoever that number belonged to. Rows staff
made by hand are never touched here.

Nothing in this module commits; callers own the transaction.
"""

from sqlalchemy import or_, select
from sqlalchemy.orm import Session

from app import notifications
from app.models import (
    CONTACT_CHANNEL_PHONE,
    MAPPING_SOURCE_CONTACT,
    ROLE_STUDENT,
    ClassTeacher,
    SchoolClass,
    Student,
    StudentMapping,
    Teacher,
    User,
)

MOTHER = "Mother"
FATHER = "Father"
# One number on both the mother's and the father's line.
PARENT = "Parent"

_PHONE_FIELDS = (("mother_mobile", MOTHER), ("father_mobile", FATHER))
_EMAIL_FIELDS = (("mother_email", MOTHER), ("father_email", FATHER))


def _verified_phone(user: User) -> str | None:
    return user.phone if user.phone and user.is_phone_verified else None


def _verified_email(user: User) -> str | None:
    return user.email if user.email and user.is_email_verified else None


def relationship_between(student: Student, user: User) -> str | None:
    """Mother, Father or Parent when this account's verified contacts are on
    the pupil's record; None when they are not, or the account is not a
    parent's."""
    if user.role != ROLE_STUDENT or not user.is_active:
        return None

    phone = _verified_phone(user)
    email = _verified_email(user)
    found: list[str] = []
    for field, relationship in _PHONE_FIELDS:
        if phone and getattr(student, field) == phone:
            found.append(relationship)
    for field, relationship in _EMAIL_FIELDS:
        if email and getattr(student, field) == email:
            found.append(relationship)

    if not found:
        return None
    if MOTHER in found and FATHER in found:
        return PARENT
    return found[0]


def _reconcile(
    db: Session,
    existing: list[StudentMapping],
    wanted: dict[tuple[str, str], str],
) -> None:
    """Brings the automatic rows in [existing] in line with [wanted]."""
    have = {(row.user_id, row.student_id): row for row in existing}

    for key, row in have.items():
        if row.source != MAPPING_SOURCE_CONTACT:
            continue
        if key not in wanted:
            db.delete(row)
        elif row.relationship != wanted[key]:
            row.relationship = wanted[key]

    for (user_id, student_id), relationship in wanted.items():
        if (user_id, student_id) not in have:
            db.add(
                StudentMapping(
                    user_id=user_id,
                    student_id=student_id,
                    relationship=relationship,
                    source=MAPPING_SOURCE_CONTACT,
                )
            )
    db.flush()


def sync_student(db: Session, student: Student) -> None:
    """Case 1: map every parent account whose verified contacts are on this
    pupil's record, and drop automatic mappings that no longer match."""
    phones = [getattr(student, f) for f, _ in _PHONE_FIELDS if getattr(student, f)]
    emails = [getattr(student, f) for f, _ in _EMAIL_FIELDS if getattr(student, f)]

    candidates: list[User] = []
    if phones or emails:
        conditions = []
        if phones:
            conditions.append(
                User.phone.in_(phones) & User.is_phone_verified.is_(True)
            )
        if emails:
            conditions.append(
                User.email.in_(emails) & User.is_email_verified.is_(True)
            )
        candidates = list(
            db.scalars(
                select(User).where(User.role == ROLE_STUDENT, or_(*conditions))
            )
        )

    wanted = {}
    for user in candidates:
        relationship = relationship_between(student, user)
        if relationship:
            wanted[(user.user_id, student.student_id)] = relationship

    existing = list(
        db.scalars(
            select(StudentMapping).where(
                StudentMapping.student_id == student.student_id
            )
        )
    )
    _reconcile(db, existing, wanted)


def sync_user(db: Session, user: User) -> None:
    """Case 2: map this account to every pupil whose record carries its
    verified phone or email, and drop automatic mappings that no longer
    match."""
    # A just-created account only gets its column defaults (is_active, the
    # verified flags) and its row when flushed; the mapping needs both.
    db.flush()
    phone = _verified_phone(user)
    email = _verified_email(user)

    students: list[Student] = []
    if user.role == ROLE_STUDENT and (phone or email):
        conditions = []
        if phone:
            conditions += [
                Student.mother_mobile == phone,
                Student.father_mobile == phone,
            ]
        if email:
            conditions += [
                Student.mother_email == email,
                Student.father_email == email,
            ]
        students = list(db.scalars(select(Student).where(or_(*conditions))))

    wanted = {}
    for student in students:
        relationship = relationship_between(student, user)
        if relationship:
            wanted[(user.user_id, student.student_id)] = relationship

    existing = list(
        db.scalars(
            select(StudentMapping).where(StudentMapping.user_id == user.user_id)
        )
    )
    _reconcile(db, existing, wanted)


def _class_teacher_user_ids(db: Session, class_id: str) -> set[str]:
    """Every account teaching this class: the class teacher and co-teachers."""
    teacher_ids = {
        teacher_id
        for teacher_id in db.scalars(
            select(SchoolClass.teacher_id).where(SchoolClass.class_id == class_id)
        )
        if teacher_id
    }
    teacher_ids |= set(
        db.scalars(
            select(ClassTeacher.teacher_id).where(ClassTeacher.class_id == class_id)
        )
    )
    if not teacher_ids:
        return set()
    return set(
        db.scalars(
            select(Teacher.user_id).where(Teacher.teacher_id.in_(teacher_ids))
        )
    )


def carry_contact_change(
    db: Session, user: User, *, channel: str, old: str | None, new: str
) -> None:
    """A parent changed their own number or email: put the new one on every
    mapped pupil's record where the old one was, and tell the class teachers.

    Only a field holding exactly the old value changes — a mapping made by
    email does not license overwriting a different number on the record.
    Then re-syncs the account, which keeps the mapping and picks up any pupil
    the new contact matches.
    """
    fields = (
        ("mother_mobile", "father_mobile")
        if channel == CONTACT_CHANNEL_PHONE
        else ("mother_email", "father_email")
    )
    what = "mobile number" if channel == CONTACT_CHANNEL_PHONE else "email address"

    if old:
        mapped_ids = list(
            db.scalars(
                select(StudentMapping.student_id).where(
                    StudentMapping.user_id == user.user_id
                )
            )
        )
        students = (
            list(db.scalars(select(Student).where(Student.student_id.in_(mapped_ids))))
            if mapped_ids
            else []
        )
        for student in students:
            changed = [field for field in fields if getattr(student, field) == old]
            if not changed:
                continue
            for field in changed:
                setattr(student, field, new)

            relationship = (
                db.get(StudentMapping, (user.user_id, student.student_id)).relationship
                or "parent"
            )
            message = notifications.parent_contact_changed_message(
                parent_name=user.full_name,
                relationship=relationship,
                student_name=student.name,
                what=what,
                new_value=new,
            )
            recipients = _class_teacher_user_ids(db, student.class_id)
            if recipients:
                for recipient in recipients:
                    notifications.notify_user(
                        db, user_id=recipient, message=message, source=user.full_name
                    )
            else:
                # A class nobody has been given yet: the principal is who is
                # answerable for it.
                notifications.notify_principals(
                    db, message=message, source=user.full_name
                )
        db.flush()

    sync_user(db, user)
