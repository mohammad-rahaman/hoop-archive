import pytest
from fastapi.testclient import TestClient

from app.db.base import Base, import_models
from app.db.session import get_db
from app.etl.ingest import ingest_csv
from app.main import app

import_models()


@pytest.fixture()
def client(db_session, sample_csv):
    ingest_csv(db_session, sample_csv)
    app.dependency_overrides[get_db] = lambda: db_session
    with TestClient(app) as c:
        yield c
    app.dependency_overrides.clear()


def test_list_players_default(client):
    r = client.get("/players")
    assert r.status_code == 200
    body = r.json()
    assert body["total"] == 6
    assert len(body["items"]) == 6
    assert body["has_more"] is False
    # Sorted by name — first alphabetically is Dante Rook.
    assert body["items"][0]["full_name"] == "Dante Rook"


def test_search_by_name_accent_insensitive(client):
    r = client.get("/players", params={"q": "marcus"})
    body = r.json()
    assert body["total"] == 1
    assert body["items"][0]["full_name"] == "Marcus Vale"
    # Marcus Vale played for CHI and NYK across his career.
    assert set(body["items"][0]["teams"]) == {"CHI", "NYK"}


def test_filter_by_position(client):
    r = client.get("/players", params={"position": "C"})
    body = r.json()
    assert body["total"] == 1
    assert body["items"][0]["full_name"] == "Dante Rook"


def test_filter_by_team_excludes_tot_from_teams_list(client):
    r = client.get("/players", params={"team": "CHI"})
    body = r.json()
    names = {i["full_name"] for i in body["items"]}
    assert names == {"Marcus Vale", "Eli Marsh"}
    eli = next(i for i in body["items"] if i["full_name"] == "Eli Marsh")
    assert "TOT" not in eli["teams"]  # aggregate team never surfaced as a real team
    assert set(eli["teams"]) == {"CHI", "NYK"}


def test_pagination(client):
    r1 = client.get("/players", params={"page": 1, "page_size": 4})
    b1 = r1.json()
    assert b1["total"] == 6 and len(b1["items"]) == 4 and b1["has_more"] is True
    r2 = client.get("/players", params={"page": 2, "page_size": 4})
    b2 = r2.json()
    assert len(b2["items"]) == 2 and b2["has_more"] is False
    # No overlap between pages.
    assert not ({i["id"] for i in b1["items"]} & {i["id"] for i in b2["items"]})


def test_filters_endpoint(client):
    r = client.get("/players/filters")
    body = r.json()
    assert "TOT" not in body["teams"]
    assert "CHI" in body["teams"] and "LAL" in body["teams"]
    assert set(body["positions"]) >= {"C", "PG", "SG", "SF", "PF"}


def test_latest_season_and_span(client):
    r = client.get("/players", params={"q": "eli marsh"})
    item = r.json()["items"][0]
    assert item["first_year"] == 2015
    assert item["last_year"] == 2016
    assert item["latest_season"] == "2016-17"


def test_filter_by_season(client):
    body = client.get("/players", params={"season": "2020-21"}).json()
    names = {i["full_name"] for i in body["items"]}
    # Priya played 2020-21; Kenji has a 2020-21 row (all stats missing) and is
    # still a player of that season.
    assert names == {"Priya Anand", "Kenji Sato"}


def test_season_filter_combines_with_team(client):
    body = client.get("/players", params={"season": "2015-16", "team": "CHI"}).json()
    assert {i["full_name"] for i in body["items"]} == {"Eli Marsh"}


def test_malformed_season_filter_rejected(client):
    assert client.get("/players", params={"season": "2016"}).status_code == 422


def test_filter_options_list_seasons_newest_first(client):
    seasons = client.get("/players/filters").json()["seasons"]
    assert seasons[0] == "2020-21"
    assert seasons[-1] == "1980-81"
    assert seasons == sorted(seasons, reverse=True)
