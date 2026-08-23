from datetime import datetime, timezone


def utcnow() -> datetime:
    """Current UTC time as a naive datetime.

    Stored and compared as naive UTC everywhere so the same code behaves
    identically on SQLite (which has no timezone support and would hand back
    naive values anyway) and on PostgreSQL.
    """
    return datetime.now(timezone.utc).replace(tzinfo=None)
