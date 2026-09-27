"""Subjects, and the two ways one comes into being.

The principal adds a subject and it is approved at once. A teacher may instead
*propose* one, which lands as `pending` and does nothing until the principal
approves it — the two-way check the requirements ask for.

A proposal is a real row rather than a message, so it can be listed, approved,
and refused with the same machinery that serves the subject list. The
alternative — keeping proposals somewhere else until they are blessed — needs a
second store and a way to move rows between the two, and gets the answer wrong
the moment the two disagree.
"""

from fastapi import APIRouter, HTTPException, Response, status
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app import codes
from app.access import require_principal, require_staff
from app.deps import CurrentUser, DbSession
from app.models import (
    SUBJECT_APPROVED,
    SUBJECT_PENDING,
    Subject,
    Teacher,
    User,
)
from app.schemas import SubjectCreateRequest, SubjectOut
from app.timeutils import utcnow

router = APIRouter(prefix="/subjects", tags=["subjects"])


def _subjects_out(db: Session, *conditions) -> list[SubjectOut]:
    """Subjects with the name of the teacher who proposed each, where one did.

    Joined in so a principal reviewing proposals sees who made them without a
    request per row. An outer join: most subjects have no proposer, and an
    inner one would hide every subject the principal added themselves.
    """
    rows = db.execute(
        select(Subject, User.full_name)
        .outerjoin(Teacher, Teacher.teacher_id == Subject.proposed_by_teacher_id)
        .outerjoin(User, User.user_id == Teacher.user_id)
        .where(*conditions)
        .order_by(Subject.subject_id)
    ).all()

    columns = [column.key for column in Subject.__table__.columns]
    return [
        SubjectOut.model_validate(
            {key: getattr(subject, key) for key in columns}
            | {"proposed_by_name": proposer_name}
        )
        for subject, proposer_name in rows
    ]


def _reject_duplicate_name(db: Session, name: str) -> None:
    """One "Mathematics" per school, however it was capitalised.

    Checked here for a readable message; `uq_subjects_name` is what holds when
    two teachers propose the same subject at the same moment.

    A *pending* subject counts as taken too. Letting a second proposal through
    would give the principal two identical rows to approve, and approving both
    would then fail on the index — a confusing way to discover the answer.
    """
    existing = db.scalar(
        select(Subject).where(func.lower(Subject.name) == func.lower(name))
    )
    if existing is None:
        return

    raise HTTPException(
        status.HTTP_409_CONFLICT,
        detail=(
            f'"{existing.name}" is already waiting for approval'
            if existing.status == SUBJECT_PENDING
            else f'"{existing.name}" is already a subject'
        ),
    )


@router.get("", response_model=list[SubjectOut])
def list_subjects(user: CurrentUser, db: DbSession) -> list[SubjectOut]:
    """The subject list.

    The principal sees everything, pending proposals included — reviewing them
    is their job. A teacher sees the approved subjects plus their own
    proposals: someone else's unapproved idea is not yet a fact about the
    school, and showing it would suggest it could be taught against.
    """
    teacher = require_staff(db, user)

    if teacher is None:
        return _subjects_out(db)

    return _subjects_out(
        db,
        (Subject.status == SUBJECT_APPROVED)
        | (Subject.proposed_by_teacher_id == teacher.teacher_id),
    )


@router.post("", response_model=SubjectOut, status_code=status.HTTP_201_CREATED)
def create_subject(
    payload: SubjectCreateRequest, user: CurrentUser, db: DbSession
) -> SubjectOut:
    """Adds a subject, or proposes one.

    Who is asking decides which. The request body is identical either way, so
    a teacher cannot ask for their proposal to arrive pre-approved — there is
    no field to ask with, which is a stronger guarantee than checking one.
    """
    teacher = require_staff(db, user)
    _reject_duplicate_name(db, payload.name)

    approved = teacher is None

    subject = Subject(
        subject_id=codes.next_code(db, codes.SUBJECT),
        name=payload.name,
        status=SUBJECT_APPROVED if approved else SUBJECT_PENDING,
        proposed_by_teacher_id=None if approved else teacher.teacher_id,
        approved_by_user_id=user.user_id if approved else None,
        approved_at=utcnow() if approved else None,
    )
    db.add(subject)

    try:
        db.commit()
    except IntegrityError as error:
        db.rollback()
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            detail=f'"{payload.name}" is already a subject',
        ) from error

    db.refresh(subject)
    return _subjects_out(db, Subject.subject_id == subject.subject_id)[0]


@router.post("/{subject_id}/approve", response_model=SubjectOut)
def approve_subject(
    subject_id: str, user: CurrentUser, db: DbSession
) -> SubjectOut:
    """The principal's half of the two-way check."""
    require_principal(user, action="approve a subject")

    subject = db.get(Subject, subject_id)
    if subject is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Subject not found")

    if subject.status == SUBJECT_APPROVED:
        # Idempotent rather than an error: two taps on a slow connection should
        # not read as a failure, and the end state is the one that was wanted.
        return _subjects_out(db, Subject.subject_id == subject_id)[0]

    subject.status = SUBJECT_APPROVED
    subject.approved_by_user_id = user.user_id
    subject.approved_at = utcnow()
    db.commit()

    return _subjects_out(db, Subject.subject_id == subject_id)[0]


@router.delete("/{subject_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_subject(subject_id: str, user: CurrentUser, db: DbSession) -> Response:
    """Removes a subject, or refuses a proposal.

    One endpoint for both because they are the same act on the same row: the
    subject stops existing. Principal only — a teacher who could delete could
    remove an approved subject the whole school teaches.
    """
    require_principal(user, action="remove a subject")

    subject = db.get(Subject, subject_id)
    if subject is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Subject not found")

    db.delete(subject)
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


