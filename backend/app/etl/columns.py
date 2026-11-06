"""Flexible CSV header mapping.

Kaggle NBA datasets use many different header spellings. Rather than hard-code
one schema, we map each *canonical* field to a set of accepted aliases and match
case/punctuation-insensitively. This lets the pipeline adapt to the real file
the user provides and report any columns it could not map, instead of silently
guessing or fabricating.
"""
import re
import unicodedata
from typing import Dict, List, Optional

# canonical field -> accepted header aliases (compared after normalization)
COLUMN_ALIASES: Dict[str, List[str]] = {
    "player_name": ["player", "player_name", "name", "playername"],
    "season": ["season", "year", "yr", "season_id"],
    "season_type": ["season_type", "stage", "type", "playoffs", "is_playoffs"],
    "team": ["team", "team_abbreviation", "tm", "team_abbr", "team_id"],
    "position": ["position", "pos"],
    "jersey_number": ["jersey", "jersey_number", "number", "no"],
    "gp": ["gp", "g", "games", "games_played"],
    "min": ["min", "mp", "minutes", "mpg"],
    "pts": ["pts", "points", "ppg"],
    "reb": ["reb", "trb", "rebounds", "rpg", "treb"],
    "ast": ["ast", "assists", "apg"],
    "stl": ["stl", "steals", "spg"],
    "blk": ["blk", "blocks", "bpg"],
    "tov": ["tov", "to", "turnovers", "topg"],
    "fgm": ["fgm", "fg", "field_goals_made"],
    "fga": ["fga", "field_goals_attempted"],
    "fg_pct": ["fg_pct", "fgpct", "fg%", "fg_percent", "fgp"],
    "fg3m": ["fg3m", "3pm", "tpm", "three_made", "3p"],
    "fg3a": ["fg3a", "3pa", "tpa", "three_att", "3pa_"],
    "fg3_pct": ["fg3_pct", "3p_pct", "3p%", "tp_pct", "three_pct", "3ppct"],
    "ftm": ["ftm", "ft", "free_throws_made"],
    "fta": ["fta", "free_throws_attempted"],
    "ft_pct": ["ft_pct", "ftpct", "ft%", "ft_percent"],
    "per": ["per", "player_efficiency_rating"],
    "ts_pct": ["ts_pct", "ts%", "true_shooting", "tspct"],
    "usg_pct": ["usg_pct", "usg%", "usage", "usgpct"],
}

# Fields required for a row to be ingestible at all.
REQUIRED_FIELDS = ["player_name", "season"]

# Numeric fields and whether they are integer-typed.
INTEGER_FIELDS = {"gp"}
FLOAT_FIELDS = [
    "min", "pts", "reb", "ast", "stl", "blk", "tov",
    "fgm", "fga", "fg_pct", "fg3m", "fg3a", "fg3_pct",
    "ftm", "fta", "ft_pct", "per", "ts_pct", "usg_pct",
]


def normalize_header(h: str) -> str:
    """Lowercase, strip accents, drop non-alphanumeric characters.

    ``%`` is mapped to the token ``pct`` *before* other punctuation is removed so
    that "FG%" and "FG" (field goals made) do not collapse to the same key.
    """
    h = unicodedata.normalize("NFKD", h or "")
    h = "".join(c for c in h if not unicodedata.combining(c))
    h = h.lower().replace("%", "pct")
    return re.sub(r"[^a-z0-9]", "", h)


# Pre-normalize aliases once.
_NORMALIZED_ALIASES = {
    canonical: {normalize_header(a) for a in aliases}
    for canonical, aliases in COLUMN_ALIASES.items()
}


def build_column_map(headers: List[str]) -> Dict[str, str]:
    """Map canonical field -> actual header present in the CSV.

    First matching header wins. Headers that match no canonical field are simply
    omitted (and reported separately by the validator).
    """
    mapping: Dict[str, str] = {}
    used_headers = set()
    for canonical, norm_aliases in _NORMALIZED_ALIASES.items():
        for header in headers:
            if header in used_headers:
                continue
            if normalize_header(header) in norm_aliases:
                mapping[canonical] = header
                used_headers.add(header)
                break
    return mapping


def unmapped_headers(headers: List[str], column_map: Dict[str, str]) -> List[str]:
    mapped = set(column_map.values())
    return [h for h in headers if h not in mapped]


def normalize_name_key(name: str) -> str:
    """Stable natural key for a player name (accent/case/punctuation-insensitive)."""
    name = unicodedata.normalize("NFKD", name or "")
    name = "".join(c for c in name if not unicodedata.combining(c))
    name = name.lower()
    name = re.sub(r"[.'’]", "", name)  # drop apostrophes/periods (O'Neal -> oneal)
    name = re.sub(r"[^a-z0-9]+", " ", name).strip()
    return re.sub(r"\s+", " ", name)


def parse_season(raw: str) -> Optional[tuple]:
    """Parse a season label into (canonical_label, year_start).

    Handles "1996-97", "1996-1997", "1996", "96-97". Returns None if unparseable.
    A bare 4-digit year is treated as the season's *start* year.
    """
    if raw is None:
        return None
    s = str(raw).strip()
    if not s:
        return None

    m = re.match(r"^(\d{4})\s*[-/]\s*(\d{2,4})$", s)
    if m:
        start = int(m.group(1))
        return (f"{start}-{str(start + 1)[-2:]}", start)

    m = re.match(r"^(\d{2})\s*[-/]\s*(\d{2})$", s)  # "96-97"
    if m:
        yy = int(m.group(1))
        start = 1900 + yy if yy >= 50 else 2000 + yy
        return (f"{start}-{str(start + 1)[-2:]}", start)

    m = re.match(r"^(\d{4})$", s)  # bare year -> treat as start year
    if m:
        start = int(m.group(1))
        return (f"{start}-{str(start + 1)[-2:]}", start)

    return None


def parse_season_type(raw: Optional[str]) -> str:
    """Map a season-type / playoffs indicator to 'regular' or 'playoff'.

    Defaults to 'regular' when absent or unrecognized (never fabricates playoffs).
    """
    if raw is None:
        return "regular"
    s = str(raw).strip().lower()
    if s in {"", "0", "false", "no", "reg", "regular", "regular_season", "regular season", "rs"}:
        return "regular"
    if s in {"1", "true", "yes", "po", "playoff", "playoffs", "post", "postseason"}:
        return "playoff"
    return "regular"
