"""Linking a parent's account to their child.

The app is for parents, so a "student" account is a parent operating on a
child's behalf — and nothing joins the two until somebody says so. This is
where that happens.

**Staff only, on purpose.** A parent cannot claim a child by asserting they are
the parent. Getting this wrong is the worst failure in the whole app: it hands
a stranger a child's address, attendance and contact numbers. The teacher who
registered the pupil, or the principal, makes the link — the register-student
form already collected the parents' names and numbers, so the school is the
party that actually knows.

The account is named by **email or phone**, not by `U_` id, because that is
what staff have in front of them. When the identifier matches a contact already
on the pupil's record — `mother_mobile`, `father_email` and so on — the
response says so, which is the closest thing to a check the server can offer
without guessing.

A self-service claim ("my number is on that child's record, link me") is
deliberately absent. It needs an approval step, which is phase 5.
"""

from fastapi import APIRouter, HTTPException, Response, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.access import readable_student, require_staff
from app.deps import CurrentUser, DbSession
from app.models import ROLE_STUDENT, Student, StudentGuardian, User
from app.schemas import (
    GuardianLinkRequest,
    GuardianOut,
    looks_like_email,
    normalize_phone,
)

router = APIRouter(prefix="/students", tags=["guardians"])


def _guardians_out(db: Session, student: Student) -> list[GuardianOut]:
    """Who may see this pupil, named rather than listed as user ids."""
    rows = db.execute(
        select(StudentGuardian, User)
        .join(User, User.user_id == StudentGuardian.user_id)
        .where(StudentGuardian.student_id == student.student_id)
        .order_by(StudentGuardian.created_at)
    ).all()

    return [
        GuardianOut(
            user_id=link.user_id,
            student_id=link.student_id,
            full_name=account.full_name,
            email=account.email,
            phone=account.phone,
            relation=link.relation,
            matches_registered_contact=_matches_registered_contact(
                student, account
            ),
            created_at=link.created_at,
        )
        for link, account in rows
    ]


def _matches_registered_contact(student: Student, account: User) -> bool:
    """Whether this account's email or phone is on the pupil's own record.

    Not a permission check — the link is already authorised by the staff member
    who made it. It is there so the list can show which links are corroborated
    by what the registration form collected, and which were typed in from
    somewhere else. A parent who changed their number since registering is a
    perfectly ordinary false negative, which is exactly why it cannot be a
    permission check.
    """
    emails = {
        (student.mother_email or "").lower(),
        (student.father_email or "").lower(),
    }
    phones = {
        normalize_phone(student.mother_mobile or ""),
        normalize_phone(student.father_mobile or ""),
        normalize_phone(student.guardian_mobile or ""),
    }

    if account.email and account.email.lower() in emails:
        return True
    if account.phone and normalize_phone(account.phone) in phones:
        return True
    return False


@router.get("/{student_id}/guardians", response_model=list[GuardianOut])
def list_guardians(
    student_id: str, user: CurrentUser, db: DbSession
) -> list[GuardianOut]:
    """The accounts linked to this pupil. Staff only.

    Not offered to a parent, even for their own child: it would tell one parent
    which other accounts can see their child, and who those accounts belong
    to. That is a family matter and the app has no business reporting it.
    """
    require_staff(db, user, action="see who is linked to a pupil")
    student = readable_student(db, user, student_id)
    return _guardians_out(db, student)


@router.post(
    "/{student_id}/guardians",
    response_model=list[GuardianOut],
    status_code=status.HTTP_201_CREATED,
)
def link_guardian(
    student_id: str,
    payload: GuardianLinkRequest,
    user: CurrentUser,
    db: DbSession,
) -> list[GuardianOut]:
    """Gives an account access to this pupil.

    The account must already exist and must be a **student-role** account. A
    teacher's or principal's account is refused: they already see this pupil
    through their own role, and linking them would blur two very different
    kinds of access into one table.
    """
    require_staff(db, user, action="link a parent to a pupil")
    student = readable_student(db, user, student_id)

    identifier = payload.identifier.strip()
    if looks_like_email(identifier):
        account = db.scalar(
            select(User).where(User.email == identifier.lower())
        )
    else:
        account = db.scalar(
            select(User).where(User.phone == normalize_phone(identifier))
        )

    if account is None:
        raise HTTPException(
            status.HTTP_404_NOT_FOUND,
            detail=(
                "No account with those details. The parent has to sign up "
                "first, then you can link them."
            ),
        )

    if account.role != ROLE_STUDENT:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            detail=(
                f"{account.full_name} is signed up as a "
                f"{account.role or 'account with no role'}, not as a parent. "
                "Only a student account can be linked to a pupil."
            ),
        )

    existing = db.get(StudentGuardian, (account.user_id, student.student_id))
    if existing is not None:
        # Idempotent: the relation is updated and the link stays. Two taps on a
        # slow connection should not read as a failure.
        existing.relation = payload.relation
        db.commit()
        return _guardians_out(db, student)

    db.add(
        StudentGuardian(
            user_id=account.user_id,
            student_id=student.student_id,
            relation=payload.relation,
            linked_by_user_id=user.user_id,
        )
    )
    db.commit()

    return _guardians_out(db, student)


@router.delete(
    "/{student_id}/guardians/{guardian_user_id}",
    status_code=status.HTTP_204_NO_CONTENT,
)
def unlink_guardian(
    student_id: str,
    guardian_user_id: str,
    user: CurrentUser,
    db: DbSession,
) -> Response:
    """Takes an account's access to this pupil away.

    The account itself is untouched — a parent whose child has left the school
    still has a login, just nothing to look at.
    """
    require_staff(db, user, action="unlink a parent from a pupil")
    student = readable_student(db, user, student_id)

    link = db.get(StudentGuardian, (guardian_user_id, student.student_id))
    if link is None:
        raise HTTPException(
            status.HTTP_404_NOT_FOUND, detail="That account is not linked"
        )

    db.delete(link)
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)
