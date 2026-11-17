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


# --- Season-vs-season comparison ---------------------------------------------


def test_compare_one_season_against_another(client):
    # Marcus Vale's 1997-98 against Priya Anand's 2020-21: each side is that
    # single season's line, not a career average.
    a = _player_id(client, "marcus")
    b = _player_id(client, "priya")
    body = client.get(
        "/players/compare",
        params={"a": a, "b": b, "a_season": "1997-98", "b_season": "2020-21"},
    ).json()
    assert body["a"]["season"] == "1997-98"
    assert body["b"]["season"] == "2020-21"
    assert body["a"]["season_team"] == "CHI"
    assert body["b"]["season_team"] == "GSW"
    m = _metrics(body)
    assert m["pts"]["a_value"] == pytest.approx(25.1)
    assert m["pts"]["b_value"] == pytest.approx(21.3)
    assert m["gp"]["a_value"] == 80  # that season's games, not the career total
    # Single-season shooting uses the recorded rate exactly.
    assert m["fg_pct"]["a_value"] == pytest.approx(0.476)
    assert m["pts"]["leader"] == "a"


def test_season_on_one_side_career_on_the_other(client):
    a = _player_id(client, "marcus")
    b = _player_id(client, "dante")
    body = client.get(
        "/players/compare", params={"a": a, "b": b, "b_season": "1996-97"}
    ).json()
    m = _metrics(body)
    assert body["a"]["season"] is None  # career
    assert m["pts"]["a_value"] == pytest.approx(
        (22.4 * 78 + 25.1 * 80 + 21.0 * 50) / 208, abs=0.01
    )
    assert m["pts"]["b_value"] == pytest.approx(26.2)


def test_traded_season_uses_tot_line_not_a_sum(client):
    # Eli Marsh split 2015-16 between CHI and NYK; the TOT row is the season.
    a = _player_id(client, "eli")
    b = _player_id(client, "priya")
    body = client.get(
        "/players/compare",
        params={"a": a, "b": b, "a_season": "2015-16", "b_season": "2020-21"},
    ).json()
    assert body["a"]["season_team"] == "TOT"
    m = _metrics(body)
    assert m["pts"]["a_value"] == pytest.approx(15.3)
    assert m["gp"]["a_value"] == 74


def test_season_the_player_never_played_is_unavailable_not_zero(client):
    a = _player_id(client, "marcus")
    b = _player_id(client, "priya")
    body = client.get(
        "/players/compare",
        params={"a": a, "b": b, "a_season": "2020-21", "b_season": "2020-21"},
    ).json()
    assert all(not m["available"] for m in body["metrics"])
    assert all(m["a_value"] is None for m in body["metrics"])
    assert body["a_wins"] == 0 and body["b_wins"] == 0


def test_same_player_two_seasons_allowed(client):
    a = _player_id(client, "marcus")
    r = client.get(
        "/players/compare",
        params={"a": a, "b": a, "a_season": "1996-97", "b_season": "1997-98"},
    )
    assert r.status_code == 200
    m = _metrics(r.json())
    assert m["pts"]["leader"] == "b"  # 25.1 beats 22.4


def test_same_player_same_season_rejected(client):
    a = _player_id(client, "marcus")
    r = client.get(
        "/players/compare",
        params={"a": a, "b": a, "a_season": "1997-98", "b_season": "1997-98"},
    )
    assert r.status_code == 400


def test_malformed_season_rejected(client):
    a = _player_id(client, "marcus")
    b = _player_id(client, "dante")
    r = client.get("/players/compare", params={"a": a, "b": b, "a_season": "2016"})
    assert r.status_code == 422
