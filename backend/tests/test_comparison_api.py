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


def _player_id(client, name_contains):
    items = client.get("/players", params={"q": name_contains}).json()["items"]
    return items[0]["id"]


def _metrics(body):
    return {m["key"]: m for m in body["metrics"]}


def test_compare_regular_careers(client):
    a = _player_id(client, "marcus")  # Marcus Vale
    b = _player_id(client, "dante")  # Dante Rook
    r = client.get("/players/compare", params={"a": a, "b": b})
    assert r.status_code == 200
    body = r.json()
    assert body["season_type"] == "regular"
    assert body["a"]["full_name"] == "Marcus Vale"
    assert body["b"]["full_name"] == "Dante Rook"

    m = _metrics(body)
    # Marcus career PTS ~23.1 (GP-weighted over 3 regular seasons).
    assert m["pts"]["a_value"] == pytest.approx(
        (22.4 * 78 + 25.1 * 80 + 21.0 * 50) / 208, abs=0.01
    )
    # Dante scores more → he (player b) leads points.
    assert m["pts"]["leader"] == "b"
    # Dante rebounds far more → he leads rebounds too.
    assert m["reb"]["leader"] == "b"
    # win tallies are internally consistent with the metric leaders.
    assert body["b_wins"] == sum(
        1 for v in m.values() if v["leader"] == "b"
    )


def test_unavailable_metrics_not_scored(client):
    a = _player_id(client, "marcus")
    b = _player_id(client, "dante")
    m = _metrics(client.get("/players/compare", params={"a": a, "b": b}).json())
    # PER and USG% are absent from the dataset → surfaced but not comparable.
    assert m["per"]["available"] is False and m["per"]["leader"] is None
    assert m["usg_pct"]["available"] is False
    # They must not contribute to either win tally.
    body = client.get("/players/compare", params={"a": a, "b": b}).json()
    assert m["per"]["key"] not in {
        k for k, v in m.items() if v["leader"] in ("a", "b")
    }
    assert body["a_wins"] + body["b_wins"] + body["ties"] <= sum(
        1 for v in m.values() if v["available"]
    )


def test_missing_split_makes_all_metrics_unavailable(client):
    # Dante Rook has no playoff rows → every metric is unavailable in that split.
    a = _player_id(client, "marcus")
    b = _player_id(client, "dante")
    body = client.get(
        "/players/compare", params={"a": a, "b": b, "season_type": "playoff"}
    ).json()
    assert body["season_type"] == "playoff"
    assert all(not m["available"] for m in body["metrics"])
    assert body["a_wins"] == 0 and body["b_wins"] == 0


def test_playoff_split_compares_two_playoff_players(client):
    a = _player_id(client, "marcus")  # playoff PTS 28.7
    b = _player_id(client, "priya")  # playoff PTS 24.1
    m = _metrics(
        client.get(
            "/players/compare", params={"a": a, "b": b, "season_type": "playoff"}
        ).json()
    )
    assert m["pts"]["available"] is True
    assert m["pts"]["a_value"] == pytest.approx(28.7, abs=0.01)
    assert m["pts"]["leader"] == "a"


def test_same_player_rejected(client):
    a = _player_id(client, "marcus")
    r = client.get("/players/compare", params={"a": a, "b": a})
    assert r.status_code == 400


def test_unknown_player_returns_404(client):
    a = _player_id(client, "marcus")
    r = client.get("/players/compare", params={"a": a, "b": 999999})
    assert r.status_code == 404


def test_invalid_season_type_rejected(client):
    a = _player_id(client, "marcus")
    b = _player_id(client, "dante")
    r = client.get(
        "/players/compare", params={"a": a, "b": b, "season_type": "preseason"}
    )
    assert r.status_code == 422
