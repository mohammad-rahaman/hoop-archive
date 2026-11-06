from app.etl import columns as C


def test_build_column_map_varied_aliases():
    headers = ["Player", "Yr", "Tm", "PTS", "TRB", "AST", "FG%", "3P%"]
    cmap = C.build_column_map(headers)
    assert cmap["player_name"] == "Player"
    assert cmap["season"] == "Yr"
    assert cmap["team"] == "Tm"
    assert cmap["pts"] == "PTS"
    assert cmap["reb"] == "TRB"
    assert cmap["fg_pct"] == "FG%"
    assert cmap["fg3_pct"] == "3P%"


def test_required_fields_detected_missing():
    cmap = C.build_column_map(["PTS", "REB"])
    missing = [r for r in C.REQUIRED_FIELDS if r not in cmap]
    assert "player_name" in missing and "season" in missing


def test_normalize_name_key_is_stable():
    assert C.normalize_name_key("Luka Dončić") == C.normalize_name_key("luka doncic")
    assert C.normalize_name_key("  O'Neal, Shaquille ") == "oneal shaquille"


def test_parse_season_formats():
    assert C.parse_season("1996-97") == ("1996-97", 1996)
    assert C.parse_season("1996-1997") == ("1996-97", 1996)
    assert C.parse_season("2019-20") == ("2019-20", 2019)
    assert C.parse_season("96-97") == ("1996-97", 1996)
    assert C.parse_season("1980") == ("1980-81", 1980)
    assert C.parse_season("") is None
    assert C.parse_season("garbage") is None


def test_parse_season_type_defaults_regular():
    assert C.parse_season_type(None) == "regular"
    assert C.parse_season_type("") == "regular"
    assert C.parse_season_type("Playoffs") == "playoff"
    assert C.parse_season_type("1") == "playoff"
    assert C.parse_season_type("RS") == "regular"
