import json
from pathlib import Path

from sqlalchemy import func, select

from app.db.models import Player, PlayerSeasonStats, SeasonType, SyncMetadata
from app.services.sync import (
    normalize_seasonal_statistics,
    run_sportradar_sync,
    sync_from_payloads,
)

SAMPLE = (
    Path(__file__).resolve().parents[1]
    / "data" / "sample" / "sportradar_seasonal_statistics_sample.json"
)


def _payload():
    return json.loads(SAMPLE.read_text())


def test_normalize_maps_fields_and_keeps_missing_null():
    rows = normalize_seasonal_statistics(_payload())
    assert len(rows) == 2
    nova = next(r for r in rows if r["player_name"] == "Nova Castillo")
    assert nova["season_label"] == "2024-25"
    assert nova["season_type"] == SeasonType.REGULAR
    assert nova["team"] == "SCH"
    assert nova["gp"] == 72
    assert nova["pts"] == 26.4
    assert nova["fg3_pct"] == 0.388
    assert nova["usg_pct"] == 29.1

    theo = next(r for r in rows if r["player_name"] == "Theo Lindqvist")
    # Theo has no three-point or advanced data → must be None, never 0.
    assert theo["fg3m"] is None
    assert theo["fg3_pct"] is None
    assert theo["ts_pct"] is None
    assert theo["usg_pct"] is None


def test_sync_from_payloads_upserts_and_records(db_session):
    result = sync_from_payloads(db_session, [_payload()])
    assert result.status == "success"
    assert result.teams_processed == 1
    assert result.rows_inserted == 2
    assert result.players_created == 2

    # Stored with provider source and provider id, missing stats as NULL.
    nova = db_session.scalar(select(Player).where(Player.full_name == "Nova Castillo"))
    assert nova.external_ids == {"sportradar": "sr:player:1001"}
    theo_stat = db_session.scalar(
        select(PlayerSeasonStats)
        .join(Player, Player.id == PlayerSeasonStats.player_id)
        .where(Player.full_name == "Theo Lindqvist")
    )
    assert theo_stat.source == "sportradar"
    assert theo_stat.fg3_pct is None
    assert theo_stat.pts == 14.9

    run = db_session.scalar(select(SyncMetadata).order_by(SyncMetadata.id.desc()))
    assert run.provider == "sportradar"
    assert run.status == "success"
    assert run.rows_ingested == 2


def test_sync_is_idempotent(db_session):
    first = sync_from_payloads(db_session, [_payload()])
    assert first.rows_inserted == 2
    second = sync_from_payloads(db_session, [_payload()])
    assert second.rows_inserted == 0
    assert second.rows_updated == 2
    # Still only two stat rows in total.
    total = db_session.scalar(select(func.count()).select_from(PlayerSeasonStats))
    assert total == 2


def test_run_sync_skips_when_unconfigured(db_session):
    from app.providers.sportradar import SportradarClient

    result = run_sportradar_sync(db_session, client=SportradarClient(api_key=None))
    assert result.status == "skipped"
    run = db_session.scalar(select(SyncMetadata).order_by(SyncMetadata.id.desc()))
    assert run.status == "skipped"
    assert "not configured" in (run.notes or "").lower()


def test_run_sync_with_injected_client(db_session):
    class _FakeClient:
        configured = True

        def seasonal_team_statistics(self, year, stype, team_id):
            return _payload()

    result = run_sportradar_sync(
        db_session,
        client=_FakeClient(),
        specs=[(2024, "REG", "sr:team:3410")],
    )
    assert result.status == "success"
    assert result.rows_inserted == 2


def test_run_sync_skips_when_no_targets(db_session):
    class _FakeClient:
        configured = True

    result = run_sportradar_sync(db_session, client=_FakeClient(), specs=[])
    assert result.status == "skipped"
    assert "target" in result.notes.lower()
