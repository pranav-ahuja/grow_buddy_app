"""Running and checking Alembic migrations from Python.

The schema used to be built by `create_schema()` at startup, which called
`create_all` and so only ever created tables that were *missing* — it could
never alter one that already existed. Adding a column or widening a CHECK
constraint therefore did nothing to a database that already had the table,
silently, which is the trap this module exists to close.

Two callers:

* `app.main`'s lifespan calls `require_current()`, which refuses to serve a
  database whose schema is behind the code.
* the test suite calls `upgrade_to_head()` against its in-memory SQLite
  database, so every test run exercises the real migrations rather than a
  second, parallel definition of the schema that could drift from them.
"""

from pathlib import Path

from alembic import command
from alembic.config import Config
from alembic.runtime.migration import MigrationContext
from alembic.script import ScriptDirectory
from sqlalchemy import Connection, Engine

# backend/, which holds alembic.ini and alembic/.
_BACKEND_ROOT = Path(__file__).resolve().parents[1]


class MigrationsOutOfDate(RuntimeError):
    """The database schema is behind the code that wants to use it."""


def alembic_config(connection: Connection | None = None) -> Config:
    """An Alembic config pinned to this project, regardless of the cwd.

    `alembic.ini` resolves `script_location` relative to the working directory,
    so a server started from anywhere but backend/ would not find the
    migrations. Both paths are made absolute here.
    """
    config = Config(str(_BACKEND_ROOT / "alembic.ini"))
    config.set_main_option("script_location", str(_BACKEND_ROOT / "alembic"))

    if connection is not None:
        # env.py picks this up and migrates the caller's connection instead of
        # opening its own. Essential for in-memory SQLite, which exists only
        # for as long as its connection does.
        config.attributes["connection"] = connection

    return config


def head_revision() -> str | None:
    """The newest revision on disk."""
    script = ScriptDirectory.from_config(alembic_config())
    return script.get_current_head()


def current_revision(connection: Connection) -> str | None:
    """The revision this database is stamped with, or None if never migrated."""
    return MigrationContext.configure(connection).get_current_revision()


def upgrade_to_head(connection: Connection) -> None:
    """Migrate [connection]'s database up to the newest revision."""
    command.upgrade(alembic_config(connection), "head")


def require_current(bind: Engine) -> None:
    """Raise unless the database is migrated up to the code's newest revision.

    Deliberately refuses to start rather than migrating automatically. An
    auto-upgrade on boot is how two workers race each other through the same
    DDL, and how an unreviewed migration reaches data nobody meant to change.
    Applying it is a decision, so it stays a command someone runs.
    """
    head = head_revision()

    with bind.connect() as connection:
        current = current_revision(connection)

    if current == head:
        return

    if current is None:
        raise MigrationsOutOfDate(
            "This database has never been migrated — it has no alembic_version "
            "table. If it is a fresh database, create the schema with:\n"
            "    .venv\\Scripts\\python.exe -m alembic upgrade head\n"
            "If it already has the pre-Alembic schema, adopt it first with:\n"
            "    .venv\\Scripts\\python.exe -m alembic stamp 0001\n"
            "    .venv\\Scripts\\python.exe -m alembic upgrade head"
        )

    raise MigrationsOutOfDate(
        f"Database schema is at revision {current}, but the code expects "
        f"{head}. Bring it up to date with:\n"
        "    .venv\\Scripts\\python.exe -m alembic upgrade head"
    )
