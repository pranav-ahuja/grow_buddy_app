"""Map parents to pupils by the contacts on the pupil's record — student_mapping

`student_guardians` becomes `student_mapping`, and `relation` becomes
`relationship`. The table already was user id + student id + relationship,
many-to-many; what changes is who fills it. Until now only staff could, one
link at a time. From here a parent account whose **verified** phone or email is
the mother's or father's on a pupil's record is mapped automatically — see
app/student_mapping.py.

- `source` says which kind a row is: `staff` (every existing row) or
  `contact_match`. Automatic rows are recomputed and may be removed; staff rows
  never are.
- `users.is_email_verified`, because an email can only map a pupil once it is
  proved. False for every existing account: nothing so far recorded whether an
  address was proved, and guessing true would let a typed-in address map a
  child. Google sign-in and a confirmed email change set it.

**Backfilled:** existing parent accounts with a verified phone are mapped to
the pupils carrying that number, so parents who already signed in with OTP see
their children without waiting for their next sign-in.

Revision ID: 0008
Revises: 0007
Create Date: 2026-09-27
"""

from datetime import datetime, timezone
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "0008"
down_revision: Union[str, None] = "0007"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "users",
        sa.Column(
            "is_email_verified",
            sa.Boolean(),
            nullable=False,
            server_default=sa.false(),
        ),
    )

    op.drop_index(
        "ix_student_guardians_student_id", table_name="student_guardians"
    )
    op.rename_table("student_guardians", "student_mapping")
    _rename_pg_constraints("student_guardians", "student_mapping")

    # Batch so SQLite, which the tests run on, can take the column rename and
    # the CHECK; on PostgreSQL these are plain ALTERs.
    with op.batch_alter_table("student_mapping") as batch:
        batch.alter_column(
            "relation",
            new_column_name="relationship",
            existing_type=sa.String(length=32),
            existing_nullable=False,
        )
        batch.add_column(
            sa.Column(
                "source",
                sa.String(length=16),
                nullable=False,
                server_default="staff",
            )
        )
        batch.create_check_constraint(
            "ck_student_mapping_source",
            "source IN ('staff', 'contact_match')",
        )

    op.create_index(
        "ix_student_mapping_student_id", "student_mapping", ["student_id"]
    )

    _backfill_phone_matches()


_PG_CONSTRAINT_SUFFIXES = (
    "pkey",
    "user_id_fkey",
    "student_id_fkey",
    "linked_by_user_id_fkey",
)


def _rename_pg_constraints(old: str, new: str) -> None:
    """PostgreSQL keeps a renamed table's constraint names, which would leave
    `student_guardians_pkey` on `student_mapping` for the next migration to
    trip over. SQLite rebuilds the table in batch mode and needs nothing."""
    if op.get_bind().dialect.name != "postgresql":
        return
    for suffix in _PG_CONSTRAINT_SUFFIXES:
        op.execute(
            f"ALTER TABLE {new} RENAME CONSTRAINT {old}_{suffix} TO {new}_{suffix}"
        )


def _backfill_phone_matches() -> None:
    """Map existing parent accounts with a verified phone to the pupils whose
    mother's or father's mobile it is. Written against the tables directly so
    the migration does not depend on application code that will keep
    changing."""
    bind = op.get_bind()
    parents = bind.execute(
        sa.text(
            "SELECT user_id, phone FROM users "
            "WHERE role = 'student' AND is_active AND is_phone_verified "
            "AND phone IS NOT NULL"
        )
    ).all()
    if not parents:
        return

    existing = {
        (row.user_id, row.student_id)
        for row in bind.execute(
            sa.text("SELECT user_id, student_id FROM student_mapping")
        )
    }
    now = datetime.now(timezone.utc).replace(tzinfo=None)

    for parent in parents:
        students = bind.execute(
            sa.text(
                "SELECT student_id, mother_mobile, father_mobile FROM students "
                "WHERE mother_mobile = :phone OR father_mobile = :phone"
            ),
            {"phone": parent.phone},
        ).all()
        for student in students:
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


def downgrade() -> None:
    # Automatic rows did not exist before this revision.
    op.execute("DELETE FROM student_mapping WHERE source = 'contact_match'")
    op.drop_index("ix_student_mapping_student_id", table_name="student_mapping")

    with op.batch_alter_table("student_mapping") as batch:
        batch.drop_constraint("ck_student_mapping_source", type_="check")
        batch.drop_column("source")
        batch.alter_column(
            "relationship",
            new_column_name="relation",
            existing_type=sa.String(length=32),
            existing_nullable=False,
        )

    op.rename_table("student_mapping", "student_guardians")
    _rename_pg_constraints("student_mapping", "student_guardians")
    op.create_index(
        "ix_student_guardians_student_id", "student_guardians", ["student_id"]
    )

    with op.batch_alter_table("users") as batch:
        batch.drop_column("is_email_verified")
