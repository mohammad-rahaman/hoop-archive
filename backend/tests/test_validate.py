from app.etl.validate import audit_csv, coerce_float, coerce_int


def test_coerce_missing_is_none_not_zero():
    for token in ["", " ", "NA", "n/a", "nan", "None", "null", "-"]:
        assert coerce_float(token) is None
        assert coerce_int(token) is None


def test_coerce_strips_percent_sign():
    assert coerce_float("46.4%") == 46.4
    assert coerce_float("0.471") == 0.471


def test_coerce_int_rounds():
    assert coerce_int("78") == 78
    assert coerce_int("78.0") == 78


def test_audit_report_on_sample(sample_csv):
    report = audit_csv(sample_csv)
    assert report.total_rows == 16
    assert report.missing_required == []
    assert report.unmapped_headers == []
    assert report.distinct_players == 6
    assert report.season_range == (1980, 2020)
    # fg3_pct is intentionally blank on several early rows.
    assert report.null_counts.get("fg3_pct", 0) >= 4
