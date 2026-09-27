"""The approval queue and the notification tab.

Two sets of routes that only make sense next to each other: a request is
raised elsewhere (see [app.routers.classes]), it arrives here as something the
principal can read and answer, and both the arrival and the answer show up in
somebody's notifications.

The split of audiences is the thing to keep straight:

* `GET /requests` — the principal sees **every** request; a teacher sees only
  their own. Not a filter the app applies, a scope the server decides, like
  every other read in this project.
* `GET /notifications` — each account's own, plus every broadcast.
* Approving and rejecting are the principal's alone.

A parent's account has no business in either and is refused outright. Nothing
here is theirs to see: the queue is staff business about staff, and a
notification addressed to a parent would be delivered by `GET /notifications`
anyway, which is why that one is *not* staff-only.
"""

from fastapi import APIRouter, HTTPException, Query, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app import approvals as approval_service
from app import notifications as notification_service
from app import school
from app.access import is_guardian, is_principal, require_principal, require_teacher
from app.deps import CurrentUser, DbSession
from app.models import (
    REQUEST_STATUSES,
    ChangeRequest,
    Notification,
    SchoolClass,
    Student,
    User,
)
from app.schemas import (
    ActionResult,
    ChangeRequestOut,
    NotificationListOut,
    NotificationOut,
    RequestDecisionRequest,
)
from app.timeutils import utcnow

router = APIRouter(tags=["approvals"])


def _refuse_guardians(user: User, *, action: str) -> None:
    if is_guardian(user):
        raise HTTPException(
            status.HTTP_403_FORBIDDEN,
            detail=f"Only a teacher or the principal can {action}",
        )


# --- The queue ----------------------------------------------------------------


@router.get("/requests", response_model=list[ChangeRequestOut])
def list_requests(
    user: CurrentUser,
    db: DbSession,
    request_status: str | None = Query(default=None, alias="status"),
) -> list[ChangeRequestOut]:
    """The requests this account may see, newest first.

    Every one in the school for the principal — that is the queue. For a
    teacher, the ones they raised, which is the "My requests" list that
    answers the question "what happened to the class I asked for?".

    `?status=pending` is what the principal's bell opens on. Left out, the
    whole history comes back, because a teacher's list is mostly interesting
    for what was *decided*.
    """
    _refuse_guardians(user, action="see approval requests")

    query = select(ChangeRequest).order_by(
        ChangeRequest.created_at.desc(), ChangeRequest.id.desc()
    )

    if request_status is not None:
        if request_status not in REQUEST_STATUSES:
            raise HTTPException(
                status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail=(
                    "status must be one of: " + ", ".join(REQUEST_STATUSES)
                ),
            )
        query = query.where(ChangeRequest.status == request_status)

    if not is_principal(user):
        teacher = require_teacher(db, user)
        query = query.where(
            ChangeRequest.requested_by_teacher_id == teacher.teacher_id
        )

    return [
        ChangeRequestOut.model_validate(row) for row in db.scalars(query)
    ]


def _pending_request(db: Session, request_id: int) -> ChangeRequest:
    request = db.get(ChangeRequest, request_id)
    if request is None:
        raise HTTPException(
            status.HTTP_404_NOT_FOUND, detail="Request not found"
        )
    return request


@router.post("/requests/{request_id}/approve", response_model=ActionResult)
def approve_request(
    request_id: int, user: CurrentUser, db: DbSession
) -> ActionResult:
    """Grants a request, and carries out what it asked for.

    Returns the same [ActionResult] the direct call would have — with the
    class or the pupil that was created — so the principal's app can show what
    it just brought into being without a second round trip.
    """
    require_principal(user, action="approve a request")
    request = _pending_request(db, request_id)

    created_class, created_student = approval_service.approve(
        db, request, decided_by=user
    )

    # Committed here, not in the service: the change, the decision and both
    # notifications are one transaction, and a partially applied approval is
    # the one outcome nobody could untangle afterwards.
    school.commit_or_409(
        db,
        "That change could not be applied — something with the same name or "
        "details was added while this request was waiting.",
    )

    detail = f"Approved: {request.summary}."
    result = ActionResult(
        status="done",
        detail=detail,
        request=ChangeRequestOut.model_validate(
            db.get(ChangeRequest, request_id)
        ),
    )

    # Read back through the same shapes the ordinary endpoints use, so an
    # approved creation is indistinguishable from a direct one.
    if created_class is not None:
        result.school_class = school.classes_out(
            db, SchoolClass.class_id == created_class.class_id
        )[0]
    if created_student is not None:
        result.student = school.students_out(
            db, Student.student_id == created_student.student_id
        )[0]

    return result


@router.post("/requests/{request_id}/reject", response_model=ChangeRequestOut)
def reject_request(
    request_id: int,
    payload: RequestDecisionRequest,
    user: CurrentUser,
    db: DbSession,
) -> ChangeRequestOut:
    """Turns a request down, with the reason where one was given.

    Nothing is executed and the row is not deleted. The teacher sees the
    answer in their own list and in their notifications; a request that simply
    vanished would read as a bug they would then repeat.
    """
    require_principal(user, action="reject a request")
    request = _pending_request(db, request_id)

    approval_service.reject(db, request, decided_by=user, note=payload.note)
    db.commit()
    db.refresh(request)

    return ChangeRequestOut.model_validate(request)


# --- The notification tab -----------------------------------------------------


@router.get("/notifications", response_model=NotificationListOut)
def list_notifications(
    user: CurrentUser,
    db: DbSession,
    limit: int = Query(default=50, ge=1, le=200),
) -> NotificationListOut:
    """This account's notifications, newest first, plus the badge numbers.

    Open to every role, parents included. A notice addressed to somebody is
    theirs to read whoever they are — and a parent whose child's registration
    was approved is exactly the kind of person this tab is for, once the rest
    of that flow exists.

    `pending_requests` is the principal's queue depth and **zero for everyone
    else**: a teacher has no business knowing how many requests the school is
    sitting on, and the app draws its badge straight from this number.
    """
    rows = list(
        db.scalars(notification_service.visible_to(user).limit(limit))
    )
    unread = sum(1 for row in rows if row.read_at is None)

    return NotificationListOut(
        notifications=[NotificationOut.model_validate(row) for row in rows],
        unread=unread,
        pending_requests=(
            approval_service.pending_count(db) if is_principal(user) else 0
        ),
    )


@router.post(
    "/notifications/{notification_id}/read", response_model=NotificationOut
)
def mark_notification_read(
    notification_id: int, user: CurrentUser, db: DbSession
) -> NotificationOut:
    """Marks one line read.

    A broadcast is refused rather than silently ignored: `read_at` is a column
    on the shared row, so marking one read would clear it for everyone. The
    per-recipient read state a broadcast would need is a table this schema
    does not have, and pretending otherwise would lose other people's unread
    notices.
    """
    notification = db.get(Notification, notification_id)
    # Not theirs reads as missing, so the endpoint cannot be used to count how
    # many notifications the school has.
    if notification is None or (
        notification.user_id is not None
        and notification.user_id != user.user_id
    ):
        raise HTTPException(
            status.HTTP_404_NOT_FOUND, detail="Notification not found"
        )

    if notification.user_id is None:
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            detail="A broadcast is read by everyone and cannot be marked read.",
        )

    if notification.read_at is None:
        notification.read_at = utcnow()
        db.commit()
        db.refresh(notification)

    return NotificationOut.model_validate(notification)


@router.post("/notifications/read", response_model=NotificationListOut)
def mark_all_read(user: CurrentUser, db: DbSession) -> NotificationListOut:
    """Clears this account's unread notices in one go — the "mark all read"
    the tab needs so a bell badge can actually be got rid of.

    Broadcasts are untouched, for the reason above.
    """
    for row in db.scalars(
        select(Notification).where(
            Notification.user_id == user.user_id,
            Notification.read_at.is_(None),
        )
    ):
        row.read_at = utcnow()
    db.commit()

    # An explicit limit: calling a FastAPI handler as a plain function would
    # otherwise hand `limit` its Query() default object rather than a number.
    return list_notifications(user, db, limit=50)
