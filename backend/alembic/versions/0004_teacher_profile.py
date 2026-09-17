"""Expand the teacher profile, and add teacher_subjects / teacher_experience

Phase 4 of the role rebuild.

`--autogenerate` got two things wrong here, and both would have failed on the
real database rather than quietly misbehaving — worth naming so the next
migration is read as carefully:

1. It added `updated_at` as **NOT NULL with no default**. There is already a
   teacher row (`TR_000001`), so PostgreSQL would have refused the whole
   statement: an existing row cannot satisfy a NOT NULL column that has no
   value. Added nullable, backfilled from `created_at` — a row that has never
   been edited was last "updated" when it was made — and only then made NOT
   NULL.

2. It emitted `create_unique_constraint(None, ...)` for the Aadhaar column, and
   `drop_constraint(None, ...)` in the downgrade. The database names an
   unnamed constraint itself, and the downgrade then has nothing to look up.
   Named `uq_teachers_aadhaar`.

Everything on `teachers` is nullable by design. These rows predate the profile,
and a sign-up cannot retroactively collect a date of birth — a migration that
demanded one could not have run at all. The API reports what is still missing
instead (`Teacher.missing_profile_fields`).

No `classes` change. "A teacher's classes, one or many" is already
`classes.teacher_id`; what phase 4 adds is the principal's ability to reassign
one, which is an endpoint, not a column.

Revision ID: 0004
Revises: 0003
Create Date: 2026-09-18
"""

from typing import Sequence, Union

import sqlalchemy as sa

from alembic import op

revision: str = "0004"
down_revision: Union[str, None] = "0003"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

AADHAAR_UNIQUE = "uq_teachers_aadhaar"

NEW_COLUMNS = (
    ("date_of_birth", sa.Date()),
    ("highest_qualification", sa.String(length=120)),
    ("address", sa.String(length=500)),
    ("relationship_status", sa.String(length=32)),
    ("aadhaar_number", sa.String(length=12)),
    ("emergency_contact_name", sa.String(length=120)),
    ("emergency_contact_phone", sa.String(length=32)),
)


def upgrade() -> None:
    # Batch mode throughout, not decoration: SQLite cannot ALTER a constraint
    # into an existing table at all, and the test suite runs on SQLite. On
    # PostgreSQL these are ordinary ALTERs.
    with op.batch_alter_table("teachers") as batch_op:
        for name, column_type in NEW_COLUMNS:
            batch_op.add_column(sa.Column(name, column_type, nullable=True))
        # Nullable first, because the rows already here have no value for it.
        batch_op.add_column(
            sa.Column("updated_at", sa.DateTime(), nullable=True)
        )
        # One Aadhaar belongs to one person. Named explicitly so the downgrade
        # can find it again.
        batch_op.create_unique_constraint(AADHAAR_UNIQUE, ["aadhaar_number"])

    op.execute(
        "UPDATE teachers SET updated_at = created_at WHERE updated_at IS NULL"
    )

    with op.batch_alter_table("teachers") as batch_op:
        batch_op.alter_column(
            "updated_at", existing_type=sa.DateTime(), nullable=False
        )

    op.create_table(
        "teacher_subjects",
        sa.Column("teacher_id", sa.String(length=16), nullable=False),
        sa.Column("subject_id", sa.String(length=16), nullable=False),
        sa.Column("assigned_by_user_id", sa.String(length=16), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(
            ["teacher_id"], ["teachers.teacher_id"], ondelete="CASCADE"
        ),
        sa.ForeignKeyConstraint(
            ["subject_id"], ["subjects.subject_id"], ondelete="CASCADE"
        ),
        # The assignment outlives the principal who made it.
        sa.ForeignKeyConstraint(
            ["assigned_by_user_id"], ["users.user_id"], ondelete="SET NULL"
        ),
        # The pair is the key, so the same subject cannot be assigned to the
        # same teacher twice.
        sa.PrimaryKeyConstraint("teacher_id", "subject_id"),
    )

    op.create_table(
        "teacher_experience",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("teacher_id", sa.String(length=16), nullable=False),
        sa.Column("school_name", sa.String(length=160), nullable=False),
        sa.Column("school_address", sa.String(length=500), nullable=False),
        # One decimal place, so "2.5 years" survives. An integer would have
        # rounded half a school year away.
        sa.Column("years", sa.Numeric(precision=4, scale=1), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(
            ["teacher_id"], ["teachers.teacher_id"], ondelete="CASCADE"
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_teacher_experience_teacher_id", "teacher_experience", ["teacher_id"]
    )


def downgrade() -> None:
    op.drop_index("ix_teacher_experience_teacher_id", table_name="teacher_experience")
    op.drop_table("teacher_experience")
    op.drop_table("teacher_subjects")

    with op.batch_alter_table("teachers") as batch_op:
        batch_op.drop_constraint(AADHAAR_UNIQUE, type_="unique")
        batch_op.drop_column("updated_at")
        for name, _ in reversed(NEW_COLUMNS):
            batch_op.drop_column(name)
