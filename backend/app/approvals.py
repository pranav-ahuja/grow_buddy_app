"""The approval queue: what a teacher may only ask for, and what happens when
the principal answers.

Four acts changed hands on 2026-09-20. Creating a class, deleting one,
registering a pupil and removing one are the principal's to do outright. A
teacher may still start all four, but what they produce is a
[app.models.ChangeRequest] — a row that says what was wanted and by whom, and
**changes nothing else at all** until somebody approves it.

That last part is the rule the whole design rests on. There is no half-created
class, no provisional pupil, no count that includes something not yet agreed.
A teacher's dashboard after they ask looks exactly as it did before, and their
request is visible in one place: the list of requests they have made.

The wording of the two sides is worth reading together:

* raising a request writes a notification to **every principal**, because any
  of them may answer it;
* answering one writes a notification back to **the teacher who asked**,
  approved or not, and a rejection carries the reason.

Execution is deliberately late. The payload is validated again at approval
time, against the school as it is then — see [app.school] — so a class name
freed or taken in the meantime is handled as it would be for any other
request, and a grant that can no longer be carried out says so instead of
half-succeeding.
"""

from fastapi import HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app import notifications, school
from app.models import (
    REQUEST_APPROVED,
    REQUEST_CLASS_CREATE,
    REQUEST_CLASS_DELETE,
    REQUEST_PENDING,
    REQUEST_REJECTED,
    REQUEST_STUDENT_ADD,
    REQUEST_STUDENT_REMOVE,
    ChangeRequest,
    SchoolClass,
    Student,
    Teacher,
    User,
)
from app.schemas import ClassCreateRequest, StudentCreateRequest
from app.timeutils import utcnow


# --- The phrase each request is described by ---------------------------------
#
# One phrase per kind, used **twice**: as the request's own `summary`, and
# inside the notification sentence. Written once so the queue and the
# notification tab cannot describe the same request differently — which is how
# a principal ends up approving something other than what they read.


def class_create_summary(name: str) -> str:
    return f'the new class "{name}"'


def class_delete_summary(name: str, student_count: int) -> str:
    if student_count == 0:
        return f'removal of the class "{name}"'
    pupils = "1 student" if student_count == 1 else f"{student_count} students"
    return f'removal of the class "{name}" and its {pupils}'


def student_add_summary(student_name: str, class_name: str) -> str:
    return f'registration of {student_name} in "{class_name}"'


def student_remove_summary(student_name: str, class_name: str) -> str:
    return f'removal of {student_name} from "{class_name}"'


# --- Raising ------------------------------------------------------------------


def raise_request(
    db: Session,
    *,
    teacher: Teacher,
    asked_by: User,
    kind: str,
    summary: str,
    payload: dict | None = None,
    class_id: str | None = None,
    student_id: str | None = None,
) -> ChangeRequest:
    """Records the asking, and tells every principal about it.

    `asked_by` is the user account behind `teacher`; its name is copied onto
    the row because the teacher link is SET NULL, and a queue reading
    "somebody wanted this class deleted" is not one anybody can act on.

    Flushed rather than committed: the notification needs the request's id,
    and the caller owns the transaction so that a failure to notify cannot
    leave a request nobody will ever see.
    """
    request = ChangeRequest(
        kind=kind,
        status=REQUEST_PENDING,
        requested_by_teacher_id=teacher.teacher_id,
        requested_by_name=asked_by.full_name,
        class_id=class_id,
        student_id=student_id,
        summary=summary,
        payload=payload or {},
    )
    db.add(request)
    db.flush()

    notifications.notify_principals(
        db,
        message=notifications.request_raised_message(
            teacher_name=asked_by.full_name, summary=summary
        ),
        # The source is the teacher, not the app: this notice is one person
        # asking another for something.
        source=asked_by.full_name,
        request_id=request.id,
    )
    return request


def pending_count(db: Session) -> int:
    """How many requests are waiting — the number on the principal's bell."""
    return (
        db.scalar(
            select(func.count())
            .select_from(ChangeRequest)
            .where(ChangeRequest.status == REQUEST_PENDING)
        )
        or 0
    )


# --- Answering ----------------------------------------------------------------


def _require_pending(request: ChangeRequest) -> None:
    """Refuses a second answer to the same request.

    Two principals opening the same queue is the ordinary case, not a rare
    one, and without this the second Approve would run the change again — a
    class created twice, or a delete that takes a class somebody has since
    recreated under the same name.
    """
    if request.status != REQUEST_PENDING:
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            detail=(
                f"This request was already {request.status}"
                + (
                    f" — {request.decision_note}"
                    if request.decision_note
                    else ""
                )
            ),
        )


def _gone(what: str) -> HTTPException:
    """The answer when the thing a request was about no longer exists.

    A 409 rather than a 404: the *request* is there and readable, it is the
    world it described that has moved on. The principal is told plainly
    instead of being shown a grant that silently did nothing.
    """
    return HTTPException(
        status.HTTP_409_CONFLICT,
        detail=f"{what} This request can only be rejected now.",
    )


def approve(
    db: Session, request: ChangeRequest, *, decided_by: User
) -> tuple[SchoolClass | None, Student | None]:
    """Carries out what was asked, and tells the teacher.

    Returns whatever the change produced — the new class, or the new pupil —
    so the caller can hand it straight back in the response rather than making
    the principal's app reload to find out what happened.

    Everything runs in one transaction with marking the request approved. A
    class that exists while the request that created it still reads "pending"
    is a state nobody can explain, and the reverse is worse.
    """
    _require_pending(request)

    created_class: SchoolClass | None = None
    created_student: Student | None = None

    if request.kind == REQUEST_CLASS_CREATE:
        if request.requested_by_teacher_id is None:
            raise _gone("The teacher who asked for this has left the school.")
        # Validated again, against the school as it is now: the name may have
        # been taken since the request was made.
        created_class = school.create_class(
            db,
            teacher_id=request.requested_by_teacher_id,
            payload=ClassCreateRequest.model_validate(request.payload),
        )
        request.class_id = created_class.class_id

    elif request.kind == REQUEST_CLASS_DELETE:
        school_class = (
            db.get(SchoolClass, request.class_id)
            if request.class_id is not None
            else None
        )
        if school_class is None:
            raise _gone("That class has already been deleted.")
        school.delete_class(db, school_class)

    elif request.kind == REQUEST_STUDENT_ADD:
        school_class = (
            db.get(SchoolClass, request.class_id)
            if request.class_id is not None
            else None
        )
        if school_class is None:
            raise _gone("The class this pupil was to join has been deleted.")
        created_student = school.create_student(
            db,
            school_class=school_class,
            payload=StudentCreateRequest.model_validate(request.payload),
        )
        request.student_id = created_student.student_id

    elif request.kind == REQUEST_STUDENT_REMOVE:
        student = (
            db.get(Student, request.student_id)
            if request.student_id is not None
            else None
        )
        if student is None:
            raise _gone("That pupil has already been removed.")
        school.delete_student(db, student)

    else:  # pragma: no cover — the CHECK constraint makes this unreachable.
        raise HTTPException(
            status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Unknown request kind: {request.kind}",
        )

    _record_decision(db, request, decided_by=decided_by, status=REQUEST_APPROVED)
    _tell_the_asker(
        db,
        request,
        message=notifications.request_approved_message(
            decided_by=decided_by.full_name, summary=request.summary
        ),
        source=decided_by.full_name,
    )
    return created_class, created_student


def reject(
    db: Session, request: ChangeRequest, *, decided_by: User, note: str = ""
) -> None:
    """Turns a request down, with the reason where one was given.

    Nothing is executed and nothing is deleted — the row stays, answered, so
    the teacher can see what became of what they asked for rather than
    watching it vanish.
    """
    _require_pending(request)

    request.decision_note = note
    _record_decision(db, request, decided_by=decided_by, status=REQUEST_REJECTED)
    _tell_the_asker(
        db,
        request,
        message=notifications.request_rejected_message(
            decided_by=decided_by.full_name,
            summary=request.summary,
            note=note,
        ),
        source=decided_by.full_name,
    )


def _record_decision(
    db: Session, request: ChangeRequest, *, decided_by: User, status: str
) -> None:
    request.status = status
    request.decided_by_user_id = decided_by.user_id
    request.decided_at = utcnow()
    db.flush()


def _tell_the_asker(
    db: Session, request: ChangeRequest, *, message: str, source: str
) -> None:
    """Notifies the teacher who raised the request, if they are still here.

    Silently does nothing when they are not. A teacher who has left still has
    requests in the queue, and a principal must be able to clear them — the
    decision is recorded either way, there is simply nobody to tell. Guarded
    rather than left to the database, because `notifications` CHECKs that an
    individual notice has a recipient, and a null one would fail the whole
    transaction and with it the decision.
    """
    if request.requested_by_teacher_id is None:
        return

    teacher = db.get(Teacher, request.requested_by_teacher_id)
    if teacher is None:
        return

    notifications.notify_user(
        db,
        user_id=teacher.user_id,
        message=message,
        source=source,
        request_id=request.id,
    )
