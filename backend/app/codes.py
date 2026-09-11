"""The readable ids every table is keyed on: U_000001, TR_000001, CL_000001,
ST_000001.

Why a counter table rather than "the highest id so far, plus one": two devices
saving at the same moment would both read the same highest id and both write
the next one. Here each prefix has one counter row, and bumping it is a single
UPDATE ... RETURNING. PostgreSQL locks that row for the rest of the transaction,
so a second writer waits and gets the following number — and if the insert that
took a number rolls back, the bump rolls back with it.

Numbers are never reused. A deleted student's id stays retired, which is what
lets a restored class file bring its students back under their old ids without
colliding with anyone registered since.
"""

import re

from sqlalchemy import select, update
from sqlalchemy.orm import Session

from app.models import IdCounter

USER = "U"
TEACHER = "TR"
CLASS = "CL"
STUDENT = "ST"

ALL_PREFIXES = (USER, TEACHER, CLASS, STUDENT)

# ST_000001 rather than ST_001: three digits run out at 999, and student ids
# count every student on the platform, not one teacher's. Six also keeps the
# ids sorting correctly as text, which ST_1000 after ST_999 would not.
CODE_DIGITS = 6

_CODE_RE = re.compile(r"^([A-Z]+)_(\d+)$")


def format_code(prefix: str, number: int) -> str:
    return f"{prefix}_{number:0{CODE_DIGITS}d}"


def number_in_code(code: str, prefix: str) -> int | None:
    """The number inside a code of this kind, or None if it is not one."""
    match = _CODE_RE.match(code)
    if match is None or match.group(1) != prefix:
        return None
    return int(match.group(2))


def next_code(db: Session, prefix: str) -> str:
    """Takes the next number for [prefix] and returns it formatted."""
    bumped = db.execute(
        update(IdCounter)
        .where(IdCounter.prefix == prefix)
        .values(last_value=IdCounter.last_value + 1)
        .returning(IdCounter.last_value)
    ).scalar_one_or_none()

    if bumped is None:
        # Only reachable on a database whose counters were never seeded —
        # create_schema() seeds them at startup, so in practice this is the
        # test suite's fresh in-memory database.
        db.add(IdCounter(prefix=prefix, last_value=1))
        db.flush()
        bumped = 1

    return format_code(prefix, bumped)


def reserve_code(db: Session, prefix: str, code: str) -> None:
    """Moves the counter past a code that arrived from outside.

    A restored class file brings its students back under their old ST_ ids.
    If the counter were somehow behind one of them — a database rebuilt from
    scratch while the file survived — the next registration would be handed
    that same id. This makes sure it cannot be.
    """
    number = number_in_code(code, prefix)
    if number is None:
        return

    counter = db.scalar(select(IdCounter).where(IdCounter.prefix == prefix))
    if counter is None:
        db.add(IdCounter(prefix=prefix, last_value=number))
    elif counter.last_value < number:
        counter.last_value = number
    db.flush()
