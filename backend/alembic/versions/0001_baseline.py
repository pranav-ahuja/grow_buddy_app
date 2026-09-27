"""baseline — the schema as it stood on 2026-09-17, before the principal role

This is the starting point, not a change. It reproduces exactly what
`create_schema()` used to build, so a fresh database can be brought up to the
same shape every later migration assumes.

The database that already exists is **stamped** with this revision rather than
run through it (`alembic stamp 0001`): its tables are already here, and running
the CREATEs would fail on the first one.

Three pieces are hand-written because `--autogenerate` cannot see them:

* `uq_classes_teacher_name` and `uq_students_same_child` are expression indexes
  (they index `lower(...)`, not a bare column). SQLAlchemy cannot reflect those
  on SQLite, so autogenerate skipped them with a warning.
* `class_roster` is a view. Alembic models tables, not views, so its SQL is
  inlined below.
* `id_counters` needs its four rows seeded, or the first sign-up has no counter
  to bump.

The view's SQL is a **copy** of `CLASS_ROSTER_VIEW` in app/database.py, not an
import. A migration has to keep doing what it did the day it was written; if it
imported the live constant, editing that constant would silently rewrite
history.

Revision ID: 0001
Revises:
Create Date: 2026-09-17
"""

from typing import Sequence, Union

import sqlalchemy as sa

from alembic import op

revision: str = "0001"
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


CLASS_ROSTER_VIEW = """
CREATE VIEW class_roster AS
SELECT
    c.class_id AS class_id,
    c.name AS class_name,
    ROW_NUMBER() OVER (
        PARTITION BY s.class_id
        ORDER BY lower(s.name), s.student_id
    ) AS roll_number,
    s.name AS student_name,
    c.teacher_id AS teacher_id,
    s.student_id AS student_id
FROM students AS s
JOIN classes AS c ON c.class_id = s.class_id
"""

ID_PREFIXES = ("U", "TR", "CL", "ST")


def upgrade() -> None:
    op.create_table(
        "id_counters",
        sa.Column("prefix", sa.String(length=8), nullable=False),
        sa.Column("last_value", sa.Integer(), nullable=False),
        sa.PrimaryKeyConstraint("prefix"),
    )

    op.create_table(
        "otp_codes",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("phone", sa.String(length=20), nullable=False),
        sa.Column("code_hash", sa.String(length=255), nullable=False),
        sa.Column("expires_at", sa.DateTime(), nullable=False),
        sa.Column("attempts", sa.Integer(), nullable=False),
        sa.Column("consumed_at", sa.DateTime(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_otp_codes_phone", "otp_codes", ["phone"], unique=False)

    op.create_table(
        "password_reset_codes",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("email", sa.String(length=255), nullable=False),
        sa.Column("code_hash", sa.String(length=255), nullable=False),
        sa.Column("expires_at", sa.DateTime(), nullable=False),
        sa.Column("attempts", sa.Integer(), nullable=False),
        sa.Column("verified_at", sa.DateTime(), nullable=True),
        sa.Column("consumed_at", sa.DateTime(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_password_reset_codes_email",
        "password_reset_codes",
        ["email"],
        unique=False,
    )

    op.create_table(
        "users",
        sa.Column("user_id", sa.String(length=16), nullable=False),
        sa.Column("uuid", sa.Uuid(), nullable=False),
        sa.Column("full_name", sa.String(length=120), nullable=False),
        sa.Column("email", sa.String(length=255), nullable=True),
        sa.Column("phone", sa.String(length=20), nullable=True),
        sa.Column("password_hash", sa.String(length=255), nullable=True),
        sa.Column("google_id", sa.String(length=255), nullable=True),
        sa.Column("role", sa.String(length=16), nullable=True),
        sa.Column("is_phone_verified", sa.Boolean(), nullable=False),
        sa.Column("is_active", sa.Boolean(), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.CheckConstraint("role IN ('teacher', 'student')", name="ck_users_role"),
        sa.PrimaryKeyConstraint("user_id"),
        sa.UniqueConstraint("uuid"),
    )
    op.create_index("ix_users_email", "users", ["email"], unique=True)
    op.create_index("ix_users_google_id", "users", ["google_id"], unique=True)
    op.create_index("ix_users_phone", "users", ["phone"], unique=True)

    op.create_table(
        "teachers",
        sa.Column("teacher_id", sa.String(length=16), nullable=False),
        sa.Column("uuid", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.String(length=16), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(
            ["user_id"], ["users.user_id"], ondelete="CASCADE"
        ),
        sa.PrimaryKeyConstraint("teacher_id"),
        sa.UniqueConstraint("user_id"),
        sa.UniqueConstraint("uuid"),
    )

    op.create_table(
        "classes",
        sa.Column("class_id", sa.String(length=16), nullable=False),
        sa.Column("uuid", sa.Uuid(), nullable=False),
        sa.Column("teacher_id", sa.String(length=16), nullable=False),
        sa.Column("name", sa.String(length=80), nullable=False),
        sa.Column("color_slot", sa.Integer(), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(
            ["teacher_id"], ["teachers.teacher_id"], ondelete="CASCADE"
        ),
        sa.PrimaryKeyConstraint("class_id"),
        sa.UniqueConstraint("uuid"),
    )
    op.create_index("ix_classes_teacher_id", "classes", ["teacher_id"], unique=False)
    # Case-insensitive: "nursery" and "Nursery" are the same tile to a teacher.
    op.create_index(
        "uq_classes_teacher_name",
        "classes",
        ["teacher_id", sa.text("lower(name)")],
        unique=True,
    )

    op.create_table(
        "students",
        sa.Column("student_id", sa.String(length=16), nullable=False),
        sa.Column("uuid", sa.Uuid(), nullable=False),
        sa.Column("class_id", sa.String(length=16), nullable=False),
        sa.Column("name", sa.String(length=120), nullable=False),
        sa.Column("date_of_birth", sa.Date(), nullable=False),
        sa.Column("gender", sa.String(length=32), nullable=False),
        sa.Column("address", sa.String(length=500), nullable=False),
        sa.Column("photo_path", sa.String(length=500), nullable=True),
        sa.Column("mother_name", sa.String(length=120), nullable=False),
        sa.Column("mother_mobile", sa.String(length=32), nullable=False),
        sa.Column("mother_email", sa.String(length=255), nullable=False),
        sa.Column("father_name", sa.String(length=120), nullable=False),
        sa.Column("father_mobile", sa.String(length=32), nullable=False),
        sa.Column("father_email", sa.String(length=255), nullable=False),
        sa.Column("guardian_name", sa.String(length=120), nullable=False),
        sa.Column("guardian_relation", sa.String(length=64), nullable=False),
        sa.Column("guardian_mobile", sa.String(length=32), nullable=False),
        sa.Column("guardian_address", sa.String(length=500), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(
            ["class_id"], ["classes.class_id"], ondelete="CASCADE"
        ),
        sa.PrimaryKeyConstraint("student_id"),
        sa.UniqueConstraint("uuid"),
    )
    op.create_index("ix_students_class_id", "students", ["class_id"], unique=False)
    # The duplicate-child rule. The name is part of the key on purpose: twins
    # share everything else and are two students.
    op.create_index(
        "uq_students_same_child",
        "students",
        [
            "class_id",
            sa.text("lower(name)"),
            "date_of_birth",
            sa.text("lower(address)"),
            sa.text("lower(mother_name)"),
            sa.text("lower(father_name)"),
            "mother_email",
            "father_email",
            "mother_mobile",
            "father_mobile",
        ],
        unique=True,
    )

    op.execute(CLASS_ROSTER_VIEW)

    # Seeded at zero. next_code() bumps a row and returns the new value, so a
    # missing row would mean the first sign-up has nothing to increment.
    op.bulk_insert(
        sa.table(
            "id_counters",
            sa.column("prefix", sa.String),
            sa.column("last_value", sa.Integer),
        ),
        [{"prefix": prefix, "last_value": 0} for prefix in ID_PREFIXES],
    )


def downgrade() -> None:
    op.execute("DROP VIEW IF EXISTS class_roster")

    op.drop_index("uq_students_same_child", table_name="students")
    op.drop_index("ix_students_class_id", table_name="students")
    op.drop_table("students")

    op.drop_index("uq_classes_teacher_name", table_name="classes")
    op.drop_index("ix_classes_teacher_id", table_name="classes")
    op.drop_table("classes")

    op.drop_table("teachers")

    op.drop_index("ix_users_phone", table_name="users")
    op.drop_index("ix_users_google_id", table_name="users")
    op.drop_index("ix_users_email", table_name="users")
    op.drop_table("users")

    op.drop_index("ix_password_reset_codes_email", table_name="password_reset_codes")
    op.drop_table("password_reset_codes")

    op.drop_index("ix_otp_codes_phone", table_name="otp_codes")
    op.drop_table("otp_codes")

    op.drop_table("id_counters")
