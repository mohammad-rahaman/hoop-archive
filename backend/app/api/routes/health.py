"""Health & metadata endpoints."""
from fastapi import APIRouter, Depends
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.config import settings
from app.db.models import Player, PlayerSeasonStats, Season, SyncMetadata, Team
from app.db.session import get_db

router = APIRouter(tags=["meta"])


@router.get("/health")
def health() -> dict:
    return {"status": "ok", "app": settings.app_name, "environment": settings.environment}


@router.get("/meta")
def meta(db: Session = Depends(get_db)) -> dict:
    counts = {
        "players": db.scalar(select(func.count()).select_from(Player)),
        "teams": db.scalar(select(func.count()).select_from(Team)),
        "seasons": db.scalar(select(func.count()).select_from(Season)),
        "player_season_stats": db.scalar(select(func.count()).select_from(PlayerSeasonStats)),
    }
    last_sync = db.scalar(select(SyncMetadata).order_by(SyncMetadata.started_at.desc()))
    season_bounds = db.execute(
        select(func.min(Season.year_start), func.max(Season.year_start))
    ).first()
    return {
        "counts": counts,
        "season_year_range": list(season_bounds) if season_bounds else None,
        "sportradar_configured": settings.sportradar_configured,
        "last_sync": (
            {
                "provider": last_sync.provider,
                "source_label": last_sync.source_label,
                "finished_at": last_sync.finished_at.isoformat() if last_sync.finished_at else None,
                "rows_ingested": last_sync.rows_ingested,
                "rows_updated": last_sync.rows_updated,
            }
            if last_sync
            else None
        ),
    }
