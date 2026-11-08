"""Sync status and manual trigger endpoints.

The Sportradar API key is never returned here; only whether it is configured and
the provenance of past runs. The manual trigger can be protected with a shared
secret (``SYNC_ADMIN_TOKEN``) so it isn't publicly invokable in production.
"""
from typing import Optional

from fastapi import APIRouter, Depends, Header, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import settings
from app.db.models import SyncMetadata
from app.db.session import get_db
from app.schemas.sync import SyncRun, SyncStatus, SyncTriggerResult
from app.services import sync as sync_service

router = APIRouter(prefix="/sync", tags=["sync"])


def _run_to_schema(run: SyncMetadata) -> SyncRun:
    return SyncRun(
        provider=run.provider,
        status=run.status,
        source_label=run.source_label,
        rows_ingested=run.rows_ingested,
        rows_updated=run.rows_updated,
        notes=run.notes,
        started_at=run.started_at.isoformat() if run.started_at else None,
        finished_at=run.finished_at.isoformat() if run.finished_at else None,
    )


@router.get("/status", response_model=SyncStatus)
def sync_status(db: Session = Depends(get_db)) -> SyncStatus:
    runs = db.scalars(
        select(SyncMetadata).order_by(SyncMetadata.started_at.desc()).limit(5)
    ).all()
    return SyncStatus(
        sportradar_configured=settings.sportradar_configured,
        scheduled_sync_active=settings.scheduled_sync_active,
        interval_hours=settings.sync_interval_hours,
        season_year=settings.sync_season_year,
        recent_runs=[_run_to_schema(r) for r in runs],
    )


@router.post("/sportradar", response_model=SyncTriggerResult)
def trigger_sportradar_sync(
    db: Session = Depends(get_db),
    x_sync_token: Optional[str] = Header(default=None),
) -> SyncTriggerResult:
    # Protect the trigger when a secret is configured.
    if settings.sync_admin_token and x_sync_token != settings.sync_admin_token:
        raise HTTPException(status_code=401, detail="Invalid or missing sync token.")

    result = sync_service.run_sportradar_sync(db)
    return SyncTriggerResult(
        provider=result.provider,
        status=result.status,
        teams_processed=result.teams_processed,
        rows_inserted=result.rows_inserted,
        rows_updated=result.rows_updated,
        players_created=result.players_created,
        notes=result.notes,
    )
