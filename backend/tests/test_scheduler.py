import asyncio

from app.core.config import settings
from app.services.scheduler import SyncScheduler


def test_scheduler_inactive_by_default():
    s = SyncScheduler()
    # No key / not enabled → does not start, no task running.
    assert s.start() is False
    assert s.running is False


def test_scheduler_start_and_stop_when_active(monkeypatch):
    monkeypatch.setattr(settings, "sync_enabled", True)
    monkeypatch.setattr(settings, "sportradar_api_key", "test-key")
    monkeypatch.setattr(settings, "sync_season_year", 2024)
    monkeypatch.setattr(settings, "sync_team_ids", "sr:team:3410")
    # Huge interval → the loop sleeps and never runs a real sync during the test.
    monkeypatch.setattr(settings, "sync_interval_hours", 10_000)
    assert settings.scheduled_sync_active is True

    async def scenario():
        s = SyncScheduler()
        assert s.start() is True
        assert s.running is True
        await s.stop()
        assert s.running is False

    asyncio.run(scenario())
