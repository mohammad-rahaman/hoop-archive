from app.services.comparison import METRICS_BY_KEY, compare_metric, compare_players


def test_higher_is_better_metric():
    pts = METRICS_BY_KEY["pts"]
    assert compare_metric(pts, 25.0, 20.0) == "a"
    assert compare_metric(pts, 20.0, 25.0) == "b"
    assert compare_metric(pts, 20.0, 20.0) == "tie"


def test_turnovers_lower_is_better():
    tov = METRICS_BY_KEY["tov"]
    assert compare_metric(tov, 2.0, 3.0) == "a"
    assert compare_metric(tov, 3.0, 2.0) == "b"


def test_missing_metric_is_not_compared_as_zero():
    pts = METRICS_BY_KEY["pts"]
    assert compare_metric(pts, None, 20.0) is None
    assert compare_metric(pts, 20.0, None) is None
    assert compare_metric(pts, None, None) is None


def test_compare_players_marks_unavailable():
    a = {"pts": 25.0, "ts_pct": None}
    b = {"pts": 22.0, "ts_pct": 0.60}
    result = {c.key: c for c in compare_players(a, b, ["pts", "ts_pct"])}
    assert result["pts"].leader == "a" and result["pts"].available is True
    assert result["ts_pct"].available is False and result["ts_pct"].leader is None
