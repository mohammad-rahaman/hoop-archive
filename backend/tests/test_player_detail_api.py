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


def test_player_detail_header_and_rows(client):
    pid = _player_id(client, "marcus")
    r = client.get(f"/players/{pid}")
    assert r.status_code == 200
    body = r.json()
    assert body["full_name"] == "Marcus Vale"
    assert body["position"] == "SG"
    assert body["has_playoffs"] is True
    assert set(body["teams"]) == {"CHI", "NYK"}
    assert body["first_year"] == 1996 and body["last_year"] == 1998
    # Rows ordered most-recent first.
    assert body["seasons"][0]["year_start"] == 1998


def test_regular_and_playoff_rows_distinct(client):
    pid = _player_id(client, "marcus")
    seasons = client.get(f"/players/{pid}").json()["seasons"]
    types_by_season = {}
    for s in seasons:
        types_by_season.setdefault(s["season"], set()).add(s["season_type"])
    assert "playoff" in types_by_season["1997-98"]
    assert "regular" in types_by_season["1997-98"]
    # Within a season, regular is ordered before playoff.
    s9798 = [s for s in seasons if s["season"] == "1997-98"]
    assert [s["season_type"] for s in s9798] == ["regular", "playoff"]


def test_multi_team_season_includes_tot_and_teams(client):
    pid = _player_id(client, "eli marsh")
    seasons = client.get(f"/players/{pid}").json()["seasons"]
    s1516 = [s for s in seasons if s["season"] == "2015-16"]
    teams = {s["team"] for s in s1516}
    assert teams == {"TOT", "CHI", "NYK"}
    # TOT listed before individual teams within the season.
    assert s1516[0]["team"] == "TOT"


def test_missing_stats_serialized_as_null(client):
    pid = _player_id(client, "kenji")
    seasons = client.get(f"/players/{pid}").json()["seasons"]
    assert len(seasons) == 1
    assert seasons[0]["pts"] is None
    assert seasons[0]["gp"] is None


def test_unknown_player_returns_404(client):
    r = client.get("/players/999999")
    assert r.status_code == 404
