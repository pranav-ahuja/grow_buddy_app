"""One phone format everywhere, and roll numbers in registration order

**Phone numbers.** Logins store numbers as `+919876543210`; the register form
stored whatever the teacher typed, usually `9876543210`. The two never compared
equal, so a parent was never mapped to their child (see 0008). The app now
normalises every number to `+91...` on the way in; this rewrites the numbers
already stored the same way — on `students` (mother, father and guardian) and
on `users` — and then maps the parents that now match.

**Roll numbers.** `class_roster` numbered pupils alphabetically, so a new pupil
could take roll 1 and push every classmate after them down one. It now numbers
them in registration order (by `student_id`, which is handed out in order and
kept by a restored class file): a new pupil gets the next number and nobody
else's changes. Removing a pupil still closes the gap behind them — the view
computes numbers, it does not store them.

Revision ID: 0009
Revises: 0008
Create Date: 2026-09-27
"""

from datetime import datetime, timezone
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "0009"
down_revision: Union[str, None] = "0008"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _roster_view(order_by: str) -> str:
    return f"""
CREATE VIEW class_roster AS
SELECT
    c.class_id AS class_id,
    c.name AS class_name,
    ROW_NUMBER() OVER (
        PARTITION BY s.class_id
        ORDER BY {order_by}
    ) AS roll_number,
    s.name AS student_name,
    c.teacher_id AS teacher_id,
    s.student_id AS student_id
FROM students AS s
JOIN classes AS c ON c.class_id = s.class_id
"""


REGISTRATION_ORDER = "s.student_id"
ALPHABETICAL_ORDER = "lower(s.name), s.student_id"


def _normalize_phone(raw: str) -> str:
    """A copy of app.schemas.normalize_phone as of this revision. Copied, not
    imported: a migration must keep doing what it did when it ran."""
    phone = "".join(ch for ch in raw.strip() if ch not in " -()\t")
    if phone.startswith("00"):
        phone = "+" + phone[2:]
    if not phone or phone.startswith("+") or not phone.isdigit():
        return phone
    if len(phone) == 10:
        return "+91" + phone
    if len(phone) == 11 and phone.startswith("0"):
        return "+91" + phone[1:]
    if len(phone) == 12 and phone.startswith("91"):
        return "+" + phone
    return phone


def upgrade() -> None:
    bind = op.get_bind()

    # --- phone numbers -------------------------------------------------------
    for row in bind.execute(
        sa.text(
            "SELECT student_id, mother_mobile, father_mobile, guardian_mobile "
            "FROM students"
        )
    ).all():
        fixed = {
            column: _normalize_phone(getattr(row, column) or "")
            for column in ("mother_mobile", "father_mobile", "guardian_mobile")
        }
        if any(fixed[c] != (getattr(row, c) or "") for c in fixed):
            bind.execute(
                sa.text(
                    "UPDATE students SET mother_mobile = :mother_mobile, "
                    "father_mobile = :father_mobile, "
                    "guardian_mobile = :guardian_mobile "
                    "WHERE student_id = :student_id"
                ),
                fixed | {"student_id": row.student_id},
            )

    taken = {
        phone
        for (phone,) in bind.execute(
            sa.text("SELECT phone FROM users WHERE phone IS NOT NULL")
        )
    }
    for row in bind.execute(
        sa.text("SELECT user_id, phone FROM users WHERE phone IS NOT NULL")
    ).all():
        fixed = _normalize_phone(row.phone)
        # users.phone is unique. If the normalised number already belongs to
        # another account, leave this one as it is rather than fail the upgrade.
        if fixed != row.phone and fixed not in taken:
            bind.execute(
                sa.text("UPDATE users SET phone = :phone WHERE user_id = :user_id"),
                {"phone": fixed, "user_id": row.user_id},
            )
            taken.discard(row.phone)
            taken.add(fixed)

    _map_matching_parents(bind)

    # --- roll numbers ----------------------------------------------------------
    op.execute("DROP VIEW IF EXISTS class_roster")
    op.execute(_roster_view(REGISTRATION_ORDER))


def _map_matching_parents(bind) -> None:
    """The same backfill 0008 ran, now that the numbers can match."""
    parents = bind.execute(
        sa.text(
            "SELECT user_id, phone FROM users "
            "WHERE role = 'student' AND is_active AND is_phone_verified "
            "AND phone IS NOT NULL"
        )
    ).all()
    existing = {
        (row.user_id, row.student_id)
        for row in bind.execute(
            sa.text("SELECT user_id, student_id FROM student_mapping")
        )
    }
    now = datetime.now(timezone.utc).replace(tzinfo=None)

    for parent in parents:
        for student in bind.execute(
            sa.text(
                "SELECT student_id, mother_mobile, father_mobile FROM students "
                "WHERE mother_mobile = :phone OR father_mobile = :phone"
            ),
            {"phone": parent.phone},
        ).all():
            if (parent.user_id, student.student_id) in existing:
                continue
            is_mother = student.mother_mobile == parent.phone
            is_father = student.father_mobile == parent.phone
            relationship = (
                "Parent" if is_mother and is_father
                else "Mother" if is_mother
                else "Father"
            )
            bind.execute(
                sa.text(
                    "INSERT INTO student_mapping "
                    "(user_id, student_id, relationship, source, created_at) "
                    "VALUES (:user_id, :student_id, :relationship, "
                    "'contact_match', :created_at)"
                ),
                {
                    "user_id": parent.user_id,
                    "student_id": student.student_id,
                    "relationship": relationship,
                    "created_at": now,
                },
            )
            existing.add((parent.user_id, student.student_id))


def downgrade() -> None:
    # The roll order goes back. The phone numbers stay normalised: the old
    # spellings are not recorded anywhere, and +91... is still a valid number
    # to every older revision.
    op.execute("DROP VIEW IF EXISTS class_roster")
    op.execute(_roster_view(ALPHABETICAL_ORDER))
