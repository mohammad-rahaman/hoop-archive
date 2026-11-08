import pytest

from app.services.comparison import (
    METRICS_BY_KEY,
    aggregate_career,
    collapse_seasons,
    compare_metric,
    compare_players,
)


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


def test_collapse_prefers_tot_regardless_of_order():
    rows = [
        {"year_start": 2015, "team": "CHI", "gp": 40},
        {"year_start": 2015, "team": "TOT", "gp": 74},
        {"year_start": 2015, "team": "NYK", "gp": 34},
        {"year_start": 2016, "team": "NYK", "gp": 77},
    ]
    collapsed = {r["year_start"]: r for r in collapse_seasons(rows)}
    assert len(collapsed) == 2
    assert collapsed[2015]["team"] == "TOT"  # aggregate kept, splits dropped
    assert collapsed[2016]["team"] == "NYK"


def test_aggregate_career_gp_weighted_and_no_double_count():
    rows = [
        # Multi-team 2015-16: TOT is the real total; CHI/NYK must not be summed.
        {"year_start": 2015, "team": "TOT", "gp": 74, "pts": 15.3, "fgm": 5.4, "fga": 12.6},
        {"year_start": 2015, "team": "CHI", "gp": 40, "pts": 16.0, "fgm": 5.7, "fga": 13.0},
        {"year_start": 2015, "team": "NYK", "gp": 34, "pts": 14.5, "fgm": 5.1, "fga": 12.1},
        {"year_start": 2016, "team": "NYK", "gp": 77, "pts": 17.1, "fgm": 6.1, "fga": 13.9},
    ]
    career = aggregate_career(rows)
    assert career["gp"] == 151  # 74 + 77, not 225
    assert career["pts"] == pytest.approx((15.3 * 74 + 17.1 * 77) / 151)
    # FG% rebuilt from volume (makes*gp / attempts*gp), not an average of rates.
    expected_fg = (5.4 * 74 + 6.1 * 77) / (12.6 * 74 + 13.9 * 77)
    assert career["fg_pct"] == pytest.approx(expected_fg)


def test_aggregate_career_missing_stays_missing():
    rows = [{"year_start": 2020, "team": "MIA", "gp": None, "pts": None, "ts_pct": None}]
    career = aggregate_career(rows)
    assert career["pts"] is None
    assert career["gp"] is None
    assert career["ts_pct"] is None


def test_aggregate_career_zero_makes_with_attempts_is_real_zero():
    # Attempts were taken but none made → a true 0.0, distinct from missing.
    rows = [{"year_start": 1980, "team": "BOS", "gp": 82, "fg3m": 0.0, "fg3a": 0.2}]
    career = aggregate_career(rows)
    assert career["fg3_pct"] == 0.0
