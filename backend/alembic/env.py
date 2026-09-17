"""Alembic's entry point, wired to the app's own settings and metadata.

The database URL is read from `app.config.settings`, **not** from alembic.ini.
One source of truth: the URL lives in `.env`, which is git-ignored, so it is
never copied into a tracked file and a migration can never run against a
different database than the server does.
"""

import sys
from logging.config import fileConfig
from pathlib import Path

from sqlalchemy import engine_from_config, pool

from alembic import context

# `alembic` is run from backend/, but the script itself lives in backend/alembic,
# so the package root is not on sys.path by default.
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.config import settings  # noqa: E402
from app.database import Base  # noqa: E402

# Imported for its side effect: every model must be registered on Base.metadata
# before autogenerate compares it against the database, or autogenerate reads
# the missing tables as "drop these".
from app import models  # noqa: E402,F401

config = context.config

# The URL from .env wins over whatever placeholder alembic.ini carries.
config.set_main_option("sqlalchemy.url", settings.database_url)

if config.config_file_name is not None:
    fileConfig(config.config_file_name)

target_metadata = Base.metadata


def include_object(obj, name, type_, reflected, compare_to) -> bool:
    """Keeps `class_roster` out of autogenerate.

    It is a view, created by raw SQL in the baseline migration. SQLAlchemy
    reflects it as a table it has no model for, so without this every
    autogenerate would helpfully offer to drop it.
    """
    if type_ == "table" and name == "class_roster":
        return False
    return True


def run_migrations_offline() -> None:
    """Emit SQL to stdout instead of running it — `alembic upgrade --sql`."""
    context.configure(
        url=settings.database_url,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
        include_object=include_object,
        compare_type=True,
    )

    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    # A caller can hand us a live connection through config.attributes — the
    # test suite does, so its in-memory SQLite database is migrated on the one
    # connection that holds it. Opening our own engine there would migrate a
    # second, empty database and leave the tests' one untouched.
    existing = config.attributes.get("connection")

    if existing is not None:
        _run(existing)
        return

    connectable = engine_from_config(
        config.get_section(config.config_ini_section, {}),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )

    with connectable.connect() as connection:
        _run(connection)


def _run(connection) -> None:
    is_sqlite = connection.dialect.name == "sqlite"

    context.configure(
        connection=connection,
        target_metadata=target_metadata,
        include_object=include_object,
        # Catches a column whose type changed, which Alembic ignores by default
        # and which is exactly the kind of drift that bites later.
        compare_type=True,
        # SQLite cannot ALTER most things in place; batch mode rewrites the
        # table instead. Harmless on PostgreSQL, and required for the test
        # suite, which runs these migrations against in-memory SQLite.
        render_as_batch=is_sqlite,
    )

    with context.begin_transaction():
        context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
