"""Writing notifications, and the one query that reads them back.

A notification is a line of text with a date, a time, a source, and an
audience — either one named account or everybody. That is the whole shape; see
[app.models.Notification] for why each column is there.

**The message is composed here and stored as written.** Every builder below
returns a finished sentence, and nothing re-renders it later. "Asha Rao
requests approval for removal of Nursery" has to still say that in a month,
after Nursery has been deleted and Asha has left — which is exactly when the
history matters and exactly when a template filled from live rows would come
back blank.

Nothing in this module commits. Notifications are raised inside the
transaction that caused them, so a request that fails to save cannot leave a
notice behind saying it was made.
"""

from sqlalchemy import Select, select
from sqlalchemy.orm import Session

from app.models import (
    NOTIFY_AUDIENCE_BROADCAST,
    NOTIFY_AUDIENCE_USER,
    ROLE_PRINCIPAL,
    Notification,
    User,
)
from app.timeutils import utcnow

# The source on anything the system says in its own voice, rather than on
# behalf of a person.
SYSTEM_SOURCE = "GrowBuddy"


def notify_user(
    db: Session,
    *,
    user_id: str,
    message: str,
    source: str = SYSTEM_SOURCE,
    request_id: int | None = None,
) -> Notification:
    """One notice for one account."""
    now = utcnow()
    notification = Notification(
        date=now.date(),
        time=now.time(),
        source=source,
        audience=NOTIFY_AUDIENCE_USER,
        user_id=user_id,
        message=message,
        request_id=request_id,
        created_at=now,
    )
    db.add(notification)
    return notification


def notify_broadcast(
    db: Session,
    *,
    message: str,
    source: str = SYSTEM_SOURCE,
) -> Notification:
    """One notice everybody reads.

    No `request_id`: an approval is one person's to decide, and a broadcast
    carrying an Approve button would put it in front of everyone.
    """
    now = utcnow()
    notification = Notification(
        date=now.date(),
        time=now.time(),
        source=source,
        audience=NOTIFY_AUDIENCE_BROADCAST,
        user_id=None,
        message=message,
        request_id=None,
        created_at=now,
    )
    db.add(notification)
    return notification


def notify_principals(
    db: Session,
    *,
    message: str,
    source: str = SYSTEM_SOURCE,
    request_id: int | None = None,
) -> list[Notification]:
    """A notice for every principal, one row each.

    Rows rather than a broadcast, because a broadcast is read by everybody and
    an approval request is not the school's business — and because `read_at`
    lives on the row. Two principals each need to mark their own copy read;
    one shared row would have the first reader clear it for the second.

    A school with no principal yet returns an empty list rather than failing.
    The request is still raised and still waits; it simply has nobody to tell,
    which is a state a brand-new school passes through.
    """
    principal_ids = list(
        db.scalars(select(User.user_id).where(User.role == ROLE_PRINCIPAL))
    )
    return [
        notify_user(
            db,
            user_id=user_id,
            message=message,
            source=source,
            request_id=request_id,
        )
        for user_id in principal_ids
    ]


def visible_to(user: User) -> Select:
    """Everything this account may read, newest first.

    Their own notices plus every broadcast. Ordered by `created_at` and not by
    date-then-time: two columns sort badly across a midnight boundary, which
    is the one moment the order visibly matters.
    """
    return (
        select(Notification)
        .where(
            (Notification.audience == NOTIFY_AUDIENCE_BROADCAST)
            | (Notification.user_id == user.user_id)
        )
        .order_by(Notification.created_at.desc(), Notification.id.desc())
    )


# --- The sentences ------------------------------------------------------------
#
# Kept together so the wording of the whole tab can be read at once. Each one
# names who is asking, what they want, and the thing it would happen to —
# enough for a principal to decide without opening anything.


def request_raised_message(*, teacher_name: str, summary: str) -> str:
    """What the principal sees when a teacher asks for something.

    Reads "Asha Rao requests approval for removal of the class Nursery" — the
    teacher's name first, because the queue is scanned by who is waiting.
    """
    return f"{teacher_name} requests approval for {summary}"


def student_registered_message(
    *, teacher_name: str, student_name: str, class_name: str
) -> str:
    """What the principal sees when a teacher registers a pupil themselves.

    Past tense, and deliberately so: registering a pupil stopped being a
    request on 2026-09-26 and became something a teacher does, so this line
    reports a fact rather than asking for one. It is raised with no
    `request_id`, which is what keeps Approve and Reject off it — there is
    nothing left to decide.

    The teacher's name comes first, as it does in the request sentences, because
    the tab is scanned by who did something.
    """
    return f'{teacher_name} registered {student_name} in "{class_name}"'


def request_approved_message(*, decided_by: str, summary: str) -> str:
    return f"{decided_by} approved your request for {summary}"


def request_rejected_message(
    *, decided_by: str, summary: str, note: str = ""
) -> str:
    """The rejection, with the reason where there is one.

    The note is included deliberately. "Rejected" on its own is how a teacher
    asks again tomorrow for the same thing in the same words.
    """
    sentence = f"{decided_by} turned down your request for {summary}"
    return f"{sentence} — {note}" if note else sentence
