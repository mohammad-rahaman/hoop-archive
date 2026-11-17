"""Database engine and session management."""
from typing import Iterator

from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker

from app.core.config import settings

engine_kwargs: dict = {"pool_pre_ping": True, "future": True}
if not settings.database_url.startswith("sqlite"):
    # Pool is sized per worker process; total DB connections across the server
    # is workers * (pool_size + max_overflow) and must stay under Postgres
    # max_connections. pool_timeout makes a request waiting for a connection
    # fail fast under overload instead of hanging indefinitely.
    engine_kwargs.update(
        {
            "pool_size": settings.db_pool_size,
            "max_overflow": settings.db_max_overflow,
            "pool_timeout": settings.db_pool_timeout,
            "pool_recycle": settings.db_pool_recycle,
        }
    )
    if settings.database_url.startswith("postgresql") and settings.db_statement_timeout_ms > 0:
        # Cancel any query that runs longer than this, returning its connection
        # to the pool rather than letting a slow query hold it open.
        engine_kwargs["connect_args"] = {
            "options": f"-c statement_timeout={settings.db_statement_timeout_ms}"
        }

engine = create_engine(settings.database_url, **engine_kwargs)

SessionLocal = sessionmaker(
    bind=engine,
    autoflush=False,
    autocommit=False,
    expire_on_commit=False,
    future=True,
)


def get_db() -> Iterator[Session]:
    """FastAPI dependency that yields a scoped session and always closes it."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.rollback()
        db.close()
