from __future__ import annotations

import os

os.environ.setdefault("DATABASE_URL", "sqlite+pysqlite:///:memory:")
os.environ.setdefault("REDIS_URL", "redis://localhost:6379/15")
os.environ.setdefault("JWT_SECRET_KEY", "test-secret")
os.environ.setdefault("DEBUG", "true")
os.environ["PENDING_MIN_REPORTS_PER_CELL"] = "3"

import pytest
from fastapi.testclient import TestClient
from geoalchemy2 import Geometry
from sqlalchemy import create_engine, event
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.dialects.postgresql import UUID as PGUUID
from sqlalchemy.ext.compiler import compiles
from sqlalchemy.orm import sessionmaker

from app.core import database as core_db
from app.core.config import get_settings
from app.core.database import Base

get_settings.cache_clear()

from app.main import app


# ---- Compile PostgreSQL-only types into SQLite-friendly equivalents. -----
@compiles(JSONB, "sqlite")
def _compile_jsonb_sqlite(element, compiler, **kw):  # type: ignore[no-redef]
    return "JSON"


@compiles(PGUUID, "sqlite")
def _compile_uuid_sqlite(element, compiler, **kw):  # type: ignore[no-redef]
    return "TEXT"


@compiles(Geometry, "sqlite")
def _compile_geometry_sqlite(element, compiler, **kw):  # type: ignore[no-redef]
    return "TEXT"


def _patch_geoalchemy_sqlite_for_in_memory_tests() -> None:
    """SpatiaLite helpers are not available on plain SQLite; skip GeoAlchemy DDL."""
    try:
        import geoalchemy2.admin.dialects.sqlite as ga_sqlite
    except ImportError:
        return

    def _noop_after_create(table, bind, **kw):  # type: ignore[no-untyped-def]
        return

    ga_sqlite.after_create = _noop_after_create  # type: ignore[assignment]


_patch_geoalchemy_sqlite_for_in_memory_tests()


def _build_engine():
    # StaticPool is important: a single shared in-memory DB across sessions.
    from sqlalchemy.pool import StaticPool

    engine = create_engine(
        "sqlite+pysqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
        future=True,
    )

    # SQLite needs foreign keys enabled explicitly.
    @event.listens_for(engine, "connect")
    def _enable_sqlite_fks(dbapi_connection, _):  # pragma: no cover
        cursor = dbapi_connection.cursor()
        cursor.execute("PRAGMA foreign_keys=ON")
        cursor.close()

    Base.metadata.create_all(bind=engine)
    return engine


@pytest.fixture(scope="session")
def engine():
    return _build_engine()


@pytest.fixture()
def db_session(engine):
    TestSession = sessionmaker(
        bind=engine, autoflush=False, autocommit=False, expire_on_commit=False
    )
    session = TestSession()
    try:
        yield session
    finally:
        session.rollback()
        for table in reversed(Base.metadata.sorted_tables):
            session.execute(table.delete())
        session.commit()
        session.close()


@pytest.fixture()
def client(db_session, engine):
    from app.core.database import get_db

    original_engine = core_db.engine
    original_session = core_db.SessionLocal
    core_db.engine = engine
    core_db.SessionLocal = sessionmaker(
        bind=engine, autoflush=False, autocommit=False, expire_on_commit=False
    )

    def override_db():
        session = core_db.SessionLocal()
        try:
            yield session
        finally:
            session.close()

    app.dependency_overrides[get_db] = override_db
    with TestClient(app) as c:
        yield c
    app.dependency_overrides.clear()
    core_db.engine = original_engine
    core_db.SessionLocal = original_session
