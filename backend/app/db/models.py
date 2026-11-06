"""ORM models for Hoop Archive.

Design notes
------------
* Player identity is NOT the raw name. Each player carries a normalized
  ``name_key`` used as the natural key, so re-ingesting the same dataset updates
  rows instead of duplicating them. ``external_ids`` holds provider ids
  (e.g. Sportradar) when available.
* A player's season can span multiple teams. Each (player, season, team,
  season_type) combination is a distinct ``PlayerSeasonStats`` row, so multi-team
  seasons and the league "TOT" aggregate are all representable.
* Regular season and playoffs are kept distinct via ``season_type``.
* Missing statistics are stored as NULL, never 0.
"""
from __future__ import annotations

import enum
from datetime import datetime
from typing import Optional

from sqlalchemy import (
    CheckConstraint,
    DateTime,
    Enum as SAEnum,
    Float,
    ForeignKey,
    Index,
    Integer,
    JSON,
    String,
    UniqueConstraint,
    func,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base


class SeasonType(str, enum.Enum):
    REGULAR = "regular"
    PLAYOFF = "playoff"


class StatMode(str, enum.Enum):
    PER_GAME = "per_game"
    TOTALS = "totals"


class Team(Base):
    __tablename__ = "teams"

    id: Mapped[int] = mapped_column(primary_key=True)
    abbreviation: Mapped[str] = mapped_column(String(8), unique=True, index=True)
    name: Mapped[Optional[str]] = mapped_column(String(120))

    stats: Mapped[list["PlayerSeasonStats"]] = relationship(back_populates="team")


class Season(Base):
    __tablename__ = "seasons"

    id: Mapped[int] = mapped_column(primary_key=True)
    # Canonical label, e.g. "1996-97".
    label: Mapped[str] = mapped_column(String(16), unique=True, index=True)
    # Starting calendar year of the season, e.g. 1996 for "1996-97".
    year_start: Mapped[int] = mapped_column(Integer, index=True)

    stats: Mapped[list["PlayerSeasonStats"]] = relationship(back_populates="season")


class Player(Base):
    __tablename__ = "players"

    id: Mapped[int] = mapped_column(primary_key=True)
    # Normalized natural key (lowercased, punctuation/diacritics stripped).
    name_key: Mapped[str] = mapped_column(String(160), unique=True, index=True)
    full_name: Mapped[str] = mapped_column(String(160), index=True)
    position: Mapped[Optional[str]] = mapped_column(String(16), index=True)
    jersey_number: Mapped[Optional[str]] = mapped_column(String(8))
    # Provider ids, e.g. {"sportradar": "sr:player:..."}.
    external_ids: Mapped[Optional[dict]] = mapped_column(JSON)

    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    stats: Mapped[list["PlayerSeasonStats"]] = relationship(
        back_populates="player", cascade="all, delete-orphan"
    )


class PlayerSeasonStats(Base):
    __tablename__ = "player_season_stats"
    __table_args__ = (
        UniqueConstraint(
            "player_id", "season_id", "team_id", "season_type",
            name="uq_player_season_team_type",
        ),
        Index("ix_pss_player_season", "player_id", "season_id"),
        Index("ix_pss_season_team", "season_id", "team_id"),
        CheckConstraint("gp IS NULL OR gp >= 0", name="ck_pss_gp_nonneg"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)

    player_id: Mapped[int] = mapped_column(ForeignKey("players.id", ondelete="CASCADE"), index=True)
    season_id: Mapped[int] = mapped_column(ForeignKey("seasons.id"), index=True)
    team_id: Mapped[int] = mapped_column(ForeignKey("teams.id"), index=True)

    season_type: Mapped[SeasonType] = mapped_column(
        SAEnum(SeasonType, native_enum=False, length=16), default=SeasonType.REGULAR
    )
    stat_mode: Mapped[StatMode] = mapped_column(
        SAEnum(StatMode, native_enum=False, length=16), default=StatMode.PER_GAME
    )

    # Games / minutes
    gp: Mapped[Optional[int]] = mapped_column(Integer)
    min: Mapped[Optional[float]] = mapped_column(Float)

    # Core box score (NULL = not provided; never defaulted to 0)
    pts: Mapped[Optional[float]] = mapped_column(Float)
    reb: Mapped[Optional[float]] = mapped_column(Float)
    ast: Mapped[Optional[float]] = mapped_column(Float)
    stl: Mapped[Optional[float]] = mapped_column(Float)
    blk: Mapped[Optional[float]] = mapped_column(Float)
    tov: Mapped[Optional[float]] = mapped_column(Float)

    # Shooting
    fgm: Mapped[Optional[float]] = mapped_column(Float)
    fga: Mapped[Optional[float]] = mapped_column(Float)
    fg_pct: Mapped[Optional[float]] = mapped_column(Float)
    fg3m: Mapped[Optional[float]] = mapped_column(Float)
    fg3a: Mapped[Optional[float]] = mapped_column(Float)
    fg3_pct: Mapped[Optional[float]] = mapped_column(Float)
    ftm: Mapped[Optional[float]] = mapped_column(Float)
    fta: Mapped[Optional[float]] = mapped_column(Float)
    ft_pct: Mapped[Optional[float]] = mapped_column(Float)

    # Advanced (only populated when the source actually provides them)
    per: Mapped[Optional[float]] = mapped_column(Float)
    ts_pct: Mapped[Optional[float]] = mapped_column(Float)
    usg_pct: Mapped[Optional[float]] = mapped_column(Float)

    source: Mapped[str] = mapped_column(String(32), default="kaggle_csv")

    player: Mapped[Player] = relationship(back_populates="stats")
    season: Mapped[Season] = relationship(back_populates="stats")
    team: Mapped[Team] = relationship(back_populates="stats")


class SyncMetadata(Base):
    """One row per ingestion / provider sync run, for provenance and offline
    'last updated' display."""

    __tablename__ = "sync_metadata"

    id: Mapped[int] = mapped_column(primary_key=True)
    provider: Mapped[str] = mapped_column(String(32), index=True)  # kaggle_csv | sportradar
    source_label: Mapped[Optional[str]] = mapped_column(String(255))
    rows_ingested: Mapped[int] = mapped_column(Integer, default=0)
    rows_updated: Mapped[int] = mapped_column(Integer, default=0)
    status: Mapped[str] = mapped_column(String(16), default="success")
    notes: Mapped[Optional[str]] = mapped_column(String(1000))
    started_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    finished_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))
