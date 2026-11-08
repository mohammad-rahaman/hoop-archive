import pytest
from fastapi.testclient import TestClient

from app.db.session import get_db
from app.etl.ingest import ingest_csv
from app.main import app


@pytest.fixture()
def client(db_session, sample_csv):
    ingest_csv(db_session, sample_csv)
    app.dependency_overrides[get_db] = lambda: db_session
    with TestClient(app) as c:
        yield c
    app.dependency_overrides.clear()


def test_status_reports_configuration_without_leaking_key(client):
    r = client.get("/sync/status")
    assert r.status_code == 200
    body = r.json()
    # No key is configured in tests.
    assert body["sportradar_configured"] is False
    assert body["scheduled_sync_active"] is False
    assert "interval_hours" in body
    # The CSV ingest recorded a run, surfaced here.
    assert any(run["provider"] == "kaggle_csv" for run in body["recent_runs"])
    # The raw key must never appear anywhere in the payload.
    assert "api_key" not in r.text and "sportradar_api_key" not in r.text


def test_trigger_without_key_is_skipped_not_error(client):
    r = client.post("/sync/sportradar")
    assert r.status_code == 200
    body = r.json()
    assert body["status"] == "skipped"
    assert body["rows_inserted"] == 0


def test_trigger_respects_admin_token(client, monkeypatch):
    from app.core.config import settings

    monkeypatch.setattr(settings, "sync_admin_token", "s3cret")
    # Missing/wrong token is rejected.
    assert client.post("/sync/sportradar").status_code == 401
    assert client.post(
        "/sync/sportradar", headers={"X-Sync-Token": "nope"}
    ).status_code == 401
    # Correct token is accepted (still skipped — no key configured).
    ok = client.post("/sync/sportradar", headers={"X-Sync-Token": "s3cret"})
    assert ok.status_code == 200
    assert ok.json()["status"] == "skipped"


def test_meta_still_reports_sportradar_not_configured(client):
    body = client.get("/meta").json()
    assert body["sportradar_configured"] is False
