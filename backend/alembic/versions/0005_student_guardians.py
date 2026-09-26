"""Link a parent's account to their child — student_guardians

Phase 6 of the role rebuild, and the piece without which a student account can
see nothing at all. A `students` row is created by a teacher from a paper form
and has no account attached; a `users` row with role 'student' was only a role.
This is the join.

Many-to-many on purpose: a parent may have two children at the school, and a
child may have two parents who each want the app.

Nothing is backfilled. There is no safe guess about which account belongs to
which child — that is exactly the judgement the school has to make, and a
wrong one hands a stranger a child's address and attendance. Links are created
one at a time by the teacher who registered the pupil, or by the principal.

Autogenerate produced this one correctly, which is worth noting after 0004: a
plain new table with no constraint changes and no NOT NULL added to existing
rows is the case it handles well. The reverse-lookup index below is the only
addition — "who are this pupil's guardians" is a query the primary key, which
leads on `user_id`, cannot serve.

Revision ID: 0005
Revises: 0004
Create Date: 2026-09-18
"""

from typing import Sequence, Union

import sqlalchemy as sa

from alembic import op

revision: str = "0005"
down_revision: Union[str, None] = "0004"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "student_guardians",
        sa.Column("user_id", sa.String(length=16), nullable=False),
        sa.Column("student_id", sa.String(length=16), nullable=False),
        sa.Column("relation", sa.String(length=32), nullable=False),
        sa.Column("linked_by_user_id", sa.String(length=16), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(
            ["user_id"], ["users.user_id"], ondelete="CASCADE"
        ),
        sa.ForeignKeyConstraint(
            ["student_id"], ["students.student_id"], ondelete="CASCADE"
        ),
        # The link outlives the staff member who made it.
        sa.ForeignKeyConstraint(
            ["linked_by_user_id"], ["users.user_id"], ondelete="SET NULL"
        ),
        # The pair is the key, so one account cannot be linked to the same
        # child twice.
        sa.PrimaryKeyConstraint("user_id", "student_id"),
    )
    # The primary key leads on user_id, so it answers "which children may this
    # account see" but not "who are this pupil's guardians" — which is what
    # the staff-facing list and every future notification fan-out will ask.
    op.create_index(
        "ix_student_guardians_student_id", "student_guardians", ["student_id"]
    )


def downgrade() -> None:
    op.drop_index(
        "ix_student_guardians_student_id", table_name="student_guardians"
    )
    op.drop_table("student_guardians")
