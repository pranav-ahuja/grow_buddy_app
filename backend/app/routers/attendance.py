"""Taking the register, and reading it back.

A register is one class on one day, marked in a single request. Thirty pupils
marked one request at a time would be thirty chances to fail halfway, and a
half-marked day is not "incomplete" to anyone reading it later — it reads as
"the rest were absent", which is a different and much worse claim.

Marking is the teacher's act, per the requirements. The principal reads
everything and marks nothing: attendance is a first-hand observation, and an
admin recording one they did not make is how a register stops being evidence.
"""

from datetime import date as date_type

from fastapi import APIRouter, HTTPException, Query, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.access import (
    guardian_student_ids,
    is_guardian,
    readable_class,
    readable_student,
    require_teacher,
)
from app.deps import CurrentUser, DbSession
from app.models import Attendance, Student
from app.schemas import AttendanceMarkRequest, AttendanceOut
from app.timeutils import utcnow

router = APIRouter(prefix="/attendance", tags=["attendance"])


def _attendance_out(db: Session, *conditions) -> list[AttendanceOut]:
    """Marks with the pupil's name, so a register reads as people not ids."""
    rows = db.execute(
        select(Attendance, Student.name)
        .join(Student, Student.student_id == Attendance.student_id)
        .where(*conditions)
        .order_by(Attendance.date.desc(), Student.name)
    ).all()

    columns = [column.key for column in Attendance.__table__.columns]
    return [
        AttendanceOut.model_validate(
            {key: getattr(mark, key) for key in columns}
            | {"student_name": student_name}
        )
        for mark, student_name in rows
    ]


@router.post("", response_model=list[AttendanceOut])
def mark_attendance(
    payload: AttendanceMarkRequest, user: CurrentUser, db: DbSession
) -> list[AttendanceOut]:
    """Takes the register for one class on one day.

    Re-posting the same day **updates** the existing marks rather than
    failing. A teacher correcting a child they marked absent by mistake is the
    normal case, not an error — and `uq_attendance_student_date` means there is
    exactly one row to correct.

    Every pupil named must actually be in that class. A student id from another
    class would otherwise file a mark against a register they were never on.
    """
    teacher = require_teacher(db, user)
    school_class = readable_class(db, user, payload.class_id)

    in_class: set[str] = {
        student_id
        for student_id in db.scalars(
            select(Student.student_id).where(
                Student.class_id == school_class.class_id
            )
        )
    }

    marked = {entry.student_id for entry in payload.entries}
    strangers = sorted(marked - in_class)
    if strangers:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            detail=(
                f"Not in {school_class.name}: {', '.join(strangers)}. "
                "Attendance can only be taken for pupils in the class."
            ),
        )

    existing = {
        mark.student_id: mark
        for mark in db.scalars(
            select(Attendance).where(
                Attendance.date == payload.date,
                Attendance.student_id.in_(marked),
            )
        )
    }

    now = utcnow()
    for entry in payload.entries:
        mark = existing.get(entry.student_id)
        if mark is None:
            db.add(
                Attendance(
                    student_id=entry.student_id,
                    class_id=school_class.class_id,
                    teacher_id=teacher.teacher_id,
                    date=payload.date,
                    status=entry.status,
                )
            )
        else:
            mark.status = entry.status
            # Who marked it last is who owns the correction.
            mark.teacher_id = teacher.teacher_id
            mark.updated_at = now

    db.commit()

    return _attendance_out(
        db,
        Attendance.class_id == school_class.class_id,
        Attendance.date == payload.date,
    )


@router.get("", response_model=list[AttendanceOut])
def read_attendance(
    user: CurrentUser,
    db: DbSession,
    class_id: str | None = Query(
        default=None, description="One class's register."
    ),
    student_id: str | None = Query(
        default=None, description="One pupil's history."
    ),
    date: date_type | None = Query(
        default=None, description="A single day. Omit for every day."
    ),
) -> list[AttendanceOut]:
    """Reads the register, by class or by pupil.

    One of `class_id` or `student_id` is required. Without either, a teacher
    would get every mark they can see and the principal every mark in the
    school — a request nobody means to make, and an expensive way to find that
    out.

    Scope is the same as everywhere else: a teacher's own classes, the whole
    school for the principal, and for a parent their own children.
    """
    if class_id is None and student_id is None:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            detail="Pass class_id or student_id to say whose attendance to read",
        )

    conditions = []

    # A parent is narrowed to their own children whatever else they asked for.
    #
    # Applied up here rather than per-branch on purpose: a parent can reach
    # their child's class, so asking by `class_id` alone would otherwise return
    # the whole register — every classmate's name and whether they were absent.
    # Reaching the class is not permission to read the other children in it.
    # No early return for a parent with no links: an empty `IN ()` already
    # matches nothing, and letting the checks below still run keeps one answer
    # for "not your class" — 404 — whether or not the account has any links at
    # all. Short-circuiting here made an unlinked parent get 200 [] where a
    # linked one got 404, for the same question.
    if is_guardian(user):
        conditions.append(
            Attendance.student_id.in_(guardian_student_ids(db, user))
        )

    if class_id is not None:
        # Raises 404 for a class this user may not see, so the filter below can
        # be trusted.
        readable_class(db, user, class_id)
        conditions.append(Attendance.class_id == class_id)

    if student_id is not None:
        # Staff reach a pupil through the class, a parent directly through the
        # guardian link. Either way somebody else's child reads as missing
        # rather than forbidden.
        readable_student(db, user, student_id)
        conditions.append(Attendance.student_id == student_id)

    if date is not None:
        conditions.append(Attendance.date == date)

    return _attendance_out(db, *conditions)


@router.get("/summary", response_model=dict)
def attendance_summary(
    user: CurrentUser,
    db: DbSession,
    student_id: str = Query(description="The pupil to summarise."),
) -> dict:
    """One pupil's totals — what a parent opens the app to see.

    Computed rather than stored: a stored total is one more thing to keep in
    step with the marks, and it would be wrong the first time a teacher
    corrected a day.
    """
    # A parent opening the app is the main caller here, so this has to work for
    # a guardian as well as for staff.
    student = readable_student(db, user, student_id)

    marks = list(
        db.scalars(
            select(Attendance.status).where(Attendance.student_id == student_id)
        )
    )
    present = marks.count("P")
    total = len(marks)

    return {
        "student_id": student_id,
        "student_name": student.name,
        "days_recorded": total,
        "present": present,
        "absent": total - present,
        # Null rather than 0% for a pupil with no marks yet: "0% attendance"
        # is a claim, and "not recorded" is the truth.
        "percent_present": round(present * 100 / total, 1) if total else None,
    }


