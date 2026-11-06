"""Declarative base for all ORM models.

Model modules import ``Base`` from here. To ensure every model is registered on
``Base.metadata`` (Alembic autogenerate, ``create_all``), import ``app.db.models``
— or use the convenience ``import_models()`` helper below.
"""
from sqlalchemy.orm import DeclarativeBase


class Base(DeclarativeBase):
    pass


def import_models() -> None:
    """Import model modules for their metadata side effects."""
    from app.db import models  # noqa: F401
