import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app import main as app_main
from app.database import get_db
from app.main import app
from app.migrations import upgrade_to_head


@pytest.fixture()
def client(monkeypatch):
    # The app's startup refuses to serve a database whose schema is behind the
    # code. That check is about a real deployment's database; here it would
    # reach for PostgreSQL and make the whole suite depend on the server being
    # up, to check a database these tests never touch. This fixture migrates
    # its own, below.
    monkeypatch.setattr(app_main, "require_current", lambda bind: None)

    # In-memory SQLite, one shared connection so every session in a test sees
    # the same schema and data.
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )

    # The real migrations, not a second definition of the schema. Tests used to
    # call create_schema(), which built the tables straight from the models —
    # so a migration could be wrong, or missing entirely, and every test would
    # still pass against a schema no real database had ever been through.
    with engine.begin() as connection:
        upgrade_to_head(connection)

    TestingSession = sessionmaker(bind=engine, autocommit=False, autoflush=False)

    def override_get_db():
        db = TestingSession()
        try:
            yield db
        finally:
            db.close()

    app.dependency_overrides[get_db] = override_get_db
    with TestClient(app) as test_client:
        yield test_client
    app.dependency_overrides.clear()
