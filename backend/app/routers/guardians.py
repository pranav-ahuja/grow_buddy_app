"""Staff-made links between a parent's account and their child.

**Most links are no longer made here.** Since 0008 a parent account whose
verified phone or email is the mother's or father's on a pupil's record is
mapped automatically — see [app.student_mapping]. This router is for the
exceptions: a grandparent, a parent whose number is not on the record, or
seeing and removing who is linked.

**Staff only, on purpose.** A parent cannot claim a child by asserting they are
the parent; the automatic path only trusts a contact a code has reached. The
teacher who registered the pupil, or the principal, makes a manual link — and a
manual link is never removed by the automatic one.

The account is named by **email or phone**, not by `U_` id, because that is
what staff have in front of them.
"""

from fastapi import APIRouter, HTTPException, Response, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.access import readable_student, require_staff
from app.deps import CurrentUser, DbSession
from app.models import (
    MAPPING_SOURCE_STAFF,
    ROLE_STUDENT,
    Student,
    StudentMapping,
    User,
)
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
        select(StudentMapping, User)
        .join(User, User.user_id == StudentMapping.user_id)
        .where(StudentMapping.student_id == student.student_id)
        .order_by(StudentMapping.created_at)
    ).all()

    return [
        GuardianOut(
            user_id=link.user_id,
            student_id=link.student_id,
            full_name=account.full_name,
            email=account.email,
            phone=account.phone,
            relation=link.relationship,
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

    existing = db.get(StudentMapping, (account.user_id, student.student_id))
    if existing is not None:
        # Idempotent: the relation is updated and the link stays. Two taps on a
        # slow connection should not read as a failure. An automatic mapping
        # becomes a staff one, so a later change of number cannot remove it.
        existing.relationship = payload.relation
        existing.source = MAPPING_SOURCE_STAFF
        existing.linked_by_user_id = user.user_id
        db.commit()
        return _guardians_out(db, student)

    db.add(
        StudentMapping(
            user_id=account.user_id,
            student_id=student.student_id,
            relationship=payload.relation,
            source=MAPPING_SOURCE_STAFF,
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

    link = db.get(StudentMapping, (guardian_user_id, student.student_id))
    if link is None:
        raise HTTPException(
            status.HTTP_404_NOT_FOUND, detail="That account is not linked"
        )

    db.delete(link)
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)
