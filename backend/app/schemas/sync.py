"""Sync status & trigger schemas. No provider API key is ever included here."""
from typing import List, Optional

from pydantic import BaseModel


class SyncRun(BaseModel):
    provider: str
    status: str
    source_label: Optional[str] = None
    rows_ingested: int = 0
    rows_updated: int = 0
    notes: Optional[str] = None
    started_at: Optional[str] = None
    finished_at: Optional[str] = None


class SyncStatus(BaseModel):
    sportradar_configured: bool
    scheduled_sync_active: bool
    interval_hours: float
    season_year: Optional[int] = None
    recent_runs: List[SyncRun] = []


class SyncTriggerResult(BaseModel):
    provider: str
    status: str  # success | skipped | error
    teams_processed: int = 0
    rows_inserted: int = 0
    rows_updated: int = 0
    players_created: int = 0
    notes: str = ""
