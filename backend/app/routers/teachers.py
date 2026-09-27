"""The teacher record: their details, their classes, subjects and experience.

Two audiences, one set of routes. A teacher reaches their own record through
the literal id `me`; the principal reaches anyone's by their `TR_` id. That is
one route per action rather than a `/teachers/me/...` set beside a
`/teachers/{id}/...` set, which would be two implementations of every rule and
eventually two different answers to the same question.

`me` is resolved rather than routed. Declaring `/teachers/me` as its own path
would work, but only as long as it stayed declared *before* `/teachers/{id}` —
a reordering of this file would silently start treating "me" as a teacher id
and return 404 to every teacher. Resolving it in one helper cannot be
reordered into a bug.
"""

from fastapi import APIRouter, HTTPException, Response, status
from sqlalchemy import delete, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.access import is_principal, require_principal, require_teacher
from app.deps import CurrentUser, DbSession
from app.models import (
    SUBJECT_APPROVED,
    SchoolClass,
    Subject,
    Teacher,
    TeacherExperience,
    TeacherSubject,
    User,
)
from app.schemas import (
    TeacherExperienceCreateRequest,
    TeacherExperienceOut,
    TeacherOut,
    TeacherProfileUpdateRequest,
    TeacherSubjectsAssignRequest,
)
from app.timeutils import utcnow

router = APIRouter(prefix="/teachers", tags=["teachers"])

# What a teacher writes in the path to mean "my own record".
SELF = "me"


def _resolve(db: Session, user: User, teacher_id: str) -> Teacher:
    """The teacher this request is about, if the caller may see it.

    `me` is the caller's own record. Any other id is the principal's business
    only — a teacher asking for a colleague's `TR_` id gets 404 rather than
    403, so the endpoint cannot be used to find out which teachers exist.
    """
    if teacher_id == SELF:
        # require_teacher creates the TR_ row if it is somehow missing, which
        # is what makes a brand-new teacher's first profile request work.
        if is_principal(user):
            raise HTTPException(
                status.HTTP_404_NOT_FOUND,
                detail=(
                    "A principal has no teacher record. Use a TR_ id to read "
                    "a teacher's."
                ),
            )
        return require_teacher(db, user)

    if not is_principal(user):
        # A teacher may still name their own id explicitly.
        own = require_teacher(db, user)
        if own.teacher_id == teacher_id:
            return own
        raise HTTPException(
            status.HTTP_404_NOT_FOUND, detail="Teacher not found"
        )

    teacher = db.get(Teacher, teacher_id)
    if teacher is None:
        raise HTTPException(
            status.HTTP_404_NOT_FOUND, detail="Teacher not found"
        )
    return teacher


def _teacher_out(db: Session, teacher: Teacher) -> TeacherOut:
    """Assembles the whole record.

    Name, email and phone come from `users` — they are not copied onto
    `teachers`, so this joins rather than reading one row. Classes come from
    `classes.teacher_id`, which already makes them a list; subjects and
    experience from their own tables.
    """
    account = db.get(User, teacher.user_id)

    classes = db.execute(
        select(SchoolClass.class_id, SchoolClass.name)
        .where(SchoolClass.teacher_id == teacher.teacher_id)
        .order_by(SchoolClass.class_id)
    ).all()

    subjects = db.execute(
        select(Subject.subject_id, Subject.name)
        .join(TeacherSubject, TeacherSubject.subject_id == Subject.subject_id)
        .where(TeacherSubject.teacher_id == teacher.teacher_id)
        .order_by(Subject.name)
    ).all()

    experience = list(
        db.scalars(
            select(TeacherExperience)
            .where(TeacherExperience.teacher_id == teacher.teacher_id)
            # Longest post first, which is the order a CV is read in.
            .order_by(TeacherExperience.years.desc(), TeacherExperience.id)
        )
    )

    return TeacherOut(
        teacher_id=teacher.teacher_id,
        user_id=teacher.user_id,
        full_name=account.full_name if account else "",
        email=account.email if account else None,
        phone=account.phone if account else None,
        date_of_birth=teacher.date_of_birth,
        highest_qualification=teacher.highest_qualification,
        address=teacher.address,
        relationship_status=teacher.relationship_status,
        # Last four digits only — see the Teacher model.
        aadhaar_last4=teacher.aadhaar_last4,
        emergency_contact_name=teacher.emergency_contact_name,
        emergency_contact_phone=teacher.emergency_contact_phone,
        classes=[
            {"class_id": class_id, "name": name} for class_id, name in classes
        ],
        subjects=[
            {"subject_id": subject_id, "name": name}
            for subject_id, name in subjects
        ],
        experience=[
            TeacherExperienceOut(
                id=row.id,
                school_name=row.school_name,
                school_address=row.school_address,
                years=float(row.years),
            )
            for row in experience
        ],
        missing_profile_fields=teacher.missing_profile_fields,
        is_profile_complete=teacher.is_profile_complete,
        created_at=teacher.created_at,
    )


@router.get("", response_model=list[TeacherOut])
def list_teachers(user: CurrentUser, db: DbSession) -> list[TeacherOut]:
    """Every teacher in the school. The principal's list.

    Not scoped like the class list: a teacher has no business enumerating
    their colleagues' records, so this is the principal's alone rather than
    returning "just yourself" to a teacher.
    """
    require_principal(user, action="see every teacher")

    teachers = list(
        db.scalars(select(Teacher).order_by(Teacher.teacher_id))
    )
    return [_teacher_out(db, teacher) for teacher in teachers]


@router.get("/{teacher_id}", response_model=TeacherOut)
def read_teacher(teacher_id: str, user: CurrentUser, db: DbSession) -> TeacherOut:
    """One teacher's record. `me` for your own."""
    return _teacher_out(db, _resolve(db, user, teacher_id))


@router.patch("/{teacher_id}", response_model=TeacherOut)
def update_teacher(
    teacher_id: str,
    payload: TeacherProfileUpdateRequest,
    user: CurrentUser,
    db: DbSession,
) -> TeacherOut:
    """Fills in or edits the details.

    Both audiences: a teacher on their own record (sign-up step and the
    profile screen both send this), and the principal on anyone's.

    Only the fields actually present in the request are touched. An explicit
    null clears a field — `model_fields_set` is what separates "left out" from
    "set to nothing", and without that distinction a teacher could never
    remove an address they entered by mistake.
    """
    teacher = _resolve(db, user, teacher_id)

    for field in payload.model_fields_set:
        setattr(teacher, field, getattr(payload, field))

    teacher.updated_at = utcnow()

    try:
        db.commit()
    except IntegrityError as error:
        db.rollback()
        # The only unique column here.
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            detail="That Aadhaar number is already on another teacher's record",
        ) from error

    db.refresh(teacher)
    return _teacher_out(db, teacher)


# --- Work experience ---------------------------------------------------------


@router.post(
    "/{teacher_id}/experience",
    response_model=TeacherOut,
    status_code=status.HTTP_201_CREATED,
)
def add_experience(
    teacher_id: str,
    payload: TeacherExperienceCreateRequest,
    user: CurrentUser,
    db: DbSession,
) -> TeacherOut:
    """Adds a previous post.

    Returns the whole record rather than just the new row: the caller is a
    profile screen that has to redraw the list anyway, and one response beats a
    create followed by a re-read.
    """
    teacher = _resolve(db, user, teacher_id)

    db.add(
        TeacherExperience(
            teacher_id=teacher.teacher_id,
            school_name=payload.school_name,
            school_address=payload.school_address,
            years=payload.years,
        )
    )
    db.commit()

    return _teacher_out(db, teacher)


@router.delete(
    "/{teacher_id}/experience/{experience_id}",
    status_code=status.HTTP_204_NO_CONTENT,
)
def remove_experience(
    teacher_id: str,
    experience_id: int,
    user: CurrentUser,
    db: DbSession,
) -> Response:
    teacher = _resolve(db, user, teacher_id)

    row = db.get(TeacherExperience, experience_id)
    # Checked against the resolved teacher, so one teacher cannot delete a line
    # off another's record by guessing an integer.
    if row is None or row.teacher_id != teacher.teacher_id:
        raise HTTPException(
            status.HTTP_404_NOT_FOUND, detail="Experience entry not found"
        )

    db.delete(row)
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


# --- Subject assignment ------------------------------------------------------


@router.put("/{teacher_id}/subjects", response_model=TeacherOut)
def assign_subjects(
    teacher_id: str,
    payload: TeacherSubjectsAssignRequest,
    user: CurrentUser,
    db: DbSession,
) -> TeacherOut:
    """Sets which subjects a teacher teaches. The principal's call.

    PUT, and the **whole set**: a screen of checkboxes knows what it wants the
    answer to be, and making it send the difference is how an unticked subject
    stays assigned. An empty list is a valid answer — it means none.

    Only **approved** subjects can be assigned. A pending one is a teacher's
    proposal that has not been accepted, and assigning it would let the
    proposal take effect without the approval it is waiting for — which is the
    whole point of the two-way check.
    """
    require_principal(user, action="assign subjects to a teacher")
    teacher = _resolve(db, user, teacher_id)

    wanted = set(payload.subject_ids)

    if wanted:
        approved = {
            subject_id
            for subject_id in db.scalars(
                select(Subject.subject_id).where(
                    Subject.subject_id.in_(wanted),
                    Subject.status == SUBJECT_APPROVED,
                )
            )
        }
        unusable = sorted(wanted - approved)
        if unusable:
            raise HTTPException(
                status.HTTP_400_BAD_REQUEST,
                detail=(
                    f"Not an approved subject: {', '.join(unusable)}. "
                    "A proposal has to be approved before it can be assigned."
                ),
            )

    db.execute(
        delete(TeacherSubject).where(
            TeacherSubject.teacher_id == teacher.teacher_id
        )
    )
    for subject_id in payload.subject_ids:
        db.add(
            TeacherSubject(
                teacher_id=teacher.teacher_id,
                subject_id=subject_id,
                assigned_by_user_id=user.user_id,
            )
        )
    db.commit()

    return _teacher_out(db, teacher)
