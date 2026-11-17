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


def test_build_column_map_prefers_tm_over_team_name():
    # Even if full Team name precedes Tm abbreviation, Tm wins team and Team wins team_name.
    cmap = C.build_column_map(["Player", "Team", "Tm", "Year"])
    assert cmap["team"] == "Tm"
    assert cmap["team_name"] == "Team"


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
    assert C.parse_season("1991.0") == ("1991-92", 1991)
    assert C.parse_season("1980.0", bare_year_is_end=True) == ("1979-80", 1979)
    assert C.parse_season("2000.0", bare_year_is_end=True) == ("1999-00", 1999)
    assert C.parse_season("") is None
    assert C.parse_season("garbage") is None


def test_parse_season_type_defaults_regular():
    assert C.parse_season_type(None) == "regular"
    assert C.parse_season_type("") == "regular"
    assert C.parse_season_type("Playoffs") == "playoff"
    assert C.parse_season_type("1") == "playoff"
    assert C.parse_season_type("RS") == "regular"
