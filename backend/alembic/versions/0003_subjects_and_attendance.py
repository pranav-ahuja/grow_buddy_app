"""Add the subjects and attendance tables

Phase 3 of the role rebuild. Both are new tables, so `create_all` would have
managed them — but the whole point of Alembic owning the schema is that there
is one path, and a table created outside the migrations is a table no other
database will ever have.

Two pieces are hand-written, for the reasons autogenerate always misses:

* `uq_subjects_name` indexes `lower(name)`, and SQLAlchemy cannot reflect an
  expression index on SQLite, so autogenerate skipped it with a warning. It is
  the constraint that actually stops two teachers proposing "Mathematics" and
  "mathematics" at the same moment.
* `id_counters` needs its `S` row. `next_code()` bumps an existing row and
  returns the new value, so without this the first subject cannot be created
  at all — and it would fail at the point of *adding a subject*, not here.

The `S` prefix is for subjects while students are `ST`. They cannot collide:
`codes.number_in_code` matches the prefix exactly, so "ST_000001" is not a
subject id.

Revision ID: 0003
Revises: 0002
Create Date: 2026-09-18
"""

from typing import Sequence, Union

import sqlalchemy as sa

from alembic import op

revision: str = "0003"
down_revision: Union[str, None] = "0002"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

SUBJECT_PREFIX = "S"


def upgrade() -> None:
    op.create_table(
        "subjects",
        sa.Column("subject_id", sa.String(length=16), nullable=False),
        sa.Column("uuid", sa.Uuid(), nullable=False),
        sa.Column("name", sa.String(length=80), nullable=False),
        sa.Column("status", sa.String(length=16), nullable=False),
        sa.Column("proposed_by_teacher_id", sa.String(length=16), nullable=True),
        sa.Column("approved_by_user_id", sa.String(length=16), nullable=True),
        sa.Column("approved_at", sa.DateTime(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.CheckConstraint(
            "status IN ('pending', 'approved')", name="ck_subjects_status"
        ),
        # SET NULL, not CASCADE — the only non-cascade in this schema. A teacher
        # leaving the school must not take the school's subject list with them.
        sa.ForeignKeyConstraint(
            ["proposed_by_teacher_id"],
            ["teachers.teacher_id"],
            ondelete="SET NULL",
        ),
        sa.ForeignKeyConstraint(
            ["approved_by_user_id"], ["users.user_id"], ondelete="SET NULL"
        ),
        sa.PrimaryKeyConstraint("subject_id"),
        sa.UniqueConstraint("uuid"),
    )
    # One "Mathematics" per school, however it was capitalised.
    op.create_index(
        "uq_subjects_name", "subjects", [sa.text("lower(name)")], unique=True
    )

    op.create_table(
        "attendance",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("student_id", sa.String(length=16), nullable=False),
        sa.Column("class_id", sa.String(length=16), nullable=False),
        sa.Column("teacher_id", sa.String(length=16), nullable=True),
        sa.Column("date", sa.Date(), nullable=False),
        sa.Column("status", sa.String(length=1), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.CheckConstraint("status IN ('P', 'A')", name="ck_attendance_status"),
        sa.ForeignKeyConstraint(
            ["student_id"], ["students.student_id"], ondelete="CASCADE"
        ),
        sa.ForeignKeyConstraint(
            ["class_id"], ["classes.class_id"], ondelete="CASCADE"
        ),
        # SET NULL again: attendance history outlives the teacher who took it.
        sa.ForeignKeyConstraint(
            ["teacher_id"], ["teachers.teacher_id"], ondelete="SET NULL"
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_attendance_student_id", "attendance", ["student_id"])
    op.create_index("ix_attendance_class_id", "attendance", ["class_id"])
    op.create_index("ix_attendance_date", "attendance", ["date"])
    # One mark per pupil per day, so a register cannot hold two contradicting
    # answers for the same child. Re-marking updates in place.
    op.create_index(
        "uq_attendance_student_date",
        "attendance",
        ["student_id", "date"],
        unique=True,
    )

    # The counter for S_ ids. Inserted only if absent, so this is safe on a
    # database that somehow already has it.
    counters = sa.table(
        "id_counters",
        sa.column("prefix", sa.String),
        sa.column("last_value", sa.Integer),
    )
    existing = (
        op.get_bind()
        .execute(
            sa.select(counters.c.prefix).where(counters.c.prefix == SUBJECT_PREFIX)
        )
        .first()
    )
    if existing is None:
        op.bulk_insert(counters, [{"prefix": SUBJECT_PREFIX, "last_value": 0}])


def downgrade() -> None:
    op.drop_index("uq_attendance_student_date", table_name="attendance")
    op.drop_index("ix_attendance_date", table_name="attendance")
    op.drop_index("ix_attendance_class_id", table_name="attendance")
    op.drop_index("ix_attendance_student_id", table_name="attendance")
    op.drop_table("attendance")

    op.drop_index("uq_subjects_name", table_name="subjects")
    op.drop_table("subjects")

    op.execute("DELETE FROM id_counters WHERE prefix = 'S'")
