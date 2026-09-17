from collections.abc import Generator

from sqlalchemy import column, create_engine, table
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker

from app.config import settings

# check_same_thread is a SQLite-only quirk: FastAPI serves requests from a
# thread pool, and SQLite otherwise refuses connections it did not create.
connect_args = (
    {"check_same_thread": False} if settings.database_url.startswith("sqlite") else {}
)

engine = create_engine(settings.database_url, connect_args=connect_args)
SessionLocal = sessionmaker(bind=engine, autocommit=False, autoflush=False)


class Base(DeclarativeBase):
    pass


def get_db() -> Generator[Session, None, None]:
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


# One row per student: the class, the student's roll number in it, and their
# name — the "class table" view of a class. The first four columns are the ones
# asked for; teacher_id and student_id are there so the API can scope and join
# on it.
#
# A view rather than a table because roll numbers are alphabetical and
# renumber when a student leaves. Stored, every registration, rename, or
# departure would mean rewriting the roll numbers of the whole class, and a
# missed rewrite would leave two students sharing a number. Computed on every
# read, they cannot drift. student_id breaks ties, so two children with the
# same name always come out in the same order.
#
# Its SQL lives in the migration that creates it — alembic/versions/0001 — not
# here. There was a copy in this file when startup built the schema itself;
# keeping it would leave two definitions to disagree with each other, and the
# migrations are the ones the database actually ran.
#
# The view as something queries can select from and join to. Not an ORM model:
# it is read-only, and the rows it returns are not things to add or delete.
class_roster = table(
    "class_roster",
    column("class_id"),
    column("class_name"),
    column("roll_number"),
    column("student_name"),
    column("teacher_id"),
    column("student_id"),
)


# There was a create_schema() here until 2026-09-17. It built the schema with
# `create_all`, which only ever creates tables that are *missing* — so once a
# table existed, adding a column or widening a constraint did nothing at all,
# without error. Alembic owns the schema now: see app/migrations.py, and
# `alembic upgrade head` to apply.
