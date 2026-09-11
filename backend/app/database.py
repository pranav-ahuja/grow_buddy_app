from collections.abc import Generator

from sqlalchemy import Engine, column, create_engine, select, table, text
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
# missed rewrite would leave two students sharing a number. Computed here on
# every read, they cannot drift. student_id breaks ties, so two children with
# the same name always come out in the same order.
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


def create_schema(bind: Engine) -> None:
    """Tables, the roster view, and the id counters — everything a fresh
    database needs before the first request.

    Shared by startup and the test suite so both run against the same schema.

    `create_all` only creates what is missing; it never alters an existing
    table. That is fine on a database this schema created, and is why a
    schema change later on wants a migration tool (Alembic) rather than this.
    """
    # Imported here: app.models imports Base from this module.
    from app.codes import ALL_PREFIXES
    from app.models import IdCounter

    Base.metadata.create_all(bind=bind)

    with bind.begin() as connection:
        # Dropped and recreated rather than created-if-missing, so a change to
        # the definition above takes effect on the next start.
        connection.execute(text("DROP VIEW IF EXISTS class_roster"))
        connection.execute(text(CLASS_ROSTER_VIEW))

    with Session(bind) as db:
        seeded = set(db.scalars(select(IdCounter.prefix)))
        for prefix in ALL_PREFIXES:
            if prefix not in seeded:
                db.add(IdCounter(prefix=prefix, last_value=0))
        db.commit()
