"""Lightweight background sync scheduler.

Uses a plain asyncio task (no extra dependency). It only does anything when
``settings.scheduled_sync_active`` is true — i.e. a Sportradar key is present,
sync is explicitly enabled, and a season + teams are configured. In every other
case (including tests and the default dev setup) it is a no-op, so no external
calls are ever made implicitly.

The sync itself is synchronous (SQLAlchemy + httpx), so each run is executed in a
worker thread to avoid blocking the event loop.
"""
from __future__ import annotations

import asyncio
import logging

from app.core.config import settings

logger = logging.getLogger("hoop_archive.scheduler")


def _run_once_blocking() -> str:
    """Run a single sync against a fresh DB session. Returns a short summary."""
    from app.db.session import SessionLocal
    from app.services.sync import run_sportradar_sync

    with SessionLocal() as session:
        result = run_sportradar_sync(session)
        return result.summary()


async def _loop(interval_seconds: float) -> None:
    # Delay the first run slightly so startup stays fast.
    try:
        while True:
            await asyncio.sleep(interval_seconds)
            try:
                summary = await asyncio.to_thread(_run_once_blocking)
                logger.info("Scheduled sync: %s", summary)
            except Exception:  # never let a failed run kill the loop
                logger.exception("Scheduled sync run failed")
    except asyncio.CancelledError:  # graceful shutdown
        raise


class SyncScheduler:
    def __init__(self) -> None:
        self._task: asyncio.Task | None = None

    @property
    def running(self) -> bool:
        return self._task is not None and not self._task.done()

    def start(self) -> bool:
        """Start the loop if a scheduled sync is active. Returns whether it ran."""
        if self.running:
            return True
        if not settings.scheduled_sync_active:
            logger.info(
                "Scheduled sync inactive (configured=%s, enabled=%s). Serving "
                "existing data only.",
                settings.sportradar_configured,
                settings.sync_enabled,
            )
            return False
        interval = max(settings.sync_interval_hours, 0.1) * 3600.0
        self._task = asyncio.create_task(_loop(interval))
        logger.info(
            "Scheduled Sportradar sync every %.1f h for season %s.",
            settings.sync_interval_hours,
            settings.sync_season_year,
        )
        return True

    async def stop(self) -> None:
        task = self._task
        self._task = None
        if task is None:
            return
        task.cancel()
        try:
            await task
        except asyncio.CancelledError:
            pass


scheduler = SyncScheduler()
