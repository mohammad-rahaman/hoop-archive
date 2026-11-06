"""Shared test fixtures.

Tests run against an in-memory SQLite database so they need no running Postgres.
The models are intentionally portable (no PG-only types), so the same schema
created here mirrors the Alembic-managed Postgres schema.
"""
from pathlib import Path

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.db.base import Base, import_models

import_models()

BACKEND_DIR = Path(__file__).resolve().parents[1]
SAMPLE_CSV = BACKEND_DIR / "data" / "sample" / "sample_nba_synthetic.csv"


@pytest.fixture()
def db_session():
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(engine)
    TestSession = sessionmaker(bind=engine, expire_on_commit=False, future=True)
    session = TestSession()
    try:
        yield session
    finally:
        session.close()
        engine.dispose()


@pytest.fixture()
def sample_csv() -> str:
    assert SAMPLE_CSV.exists(), f"sample CSV missing at {SAMPLE_CSV}"
    return str(SAMPLE_CSV)
