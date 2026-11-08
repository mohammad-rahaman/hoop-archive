"""Player comparison calculations.

Rules (from the PDP):
* Never treat a missing (None) value as 0.
* Never compare a metric that is unavailable for either player.
* Most metrics: higher is better. Turnovers: lower is better.
* Keep regular season and playoffs distinct (the caller picks the split).
* Multi-team seasons are represented once (the "TOT" aggregate), never summed
  together with their per-team splits.
"""
from dataclasses import dataclass
from typing import Dict, List, Mapping, Optional, Sequence


@dataclass(frozen=True)
class Metric:
    key: str
    label: str
    unit: str  # "", "%", "pg" etc.
    higher_is_better: bool = True
    percent: bool = False


# Canonical comparable metrics with display metadata.
METRICS: List[Metric] = [
    Metric("pts", "Points", "pg"),
    Metric("reb", "Rebounds", "pg"),
    Metric("ast", "Assists", "pg"),
    Metric("stl", "Steals", "pg"),
    Metric("blk", "Blocks", "pg"),
    Metric("tov", "Turnovers", "pg", higher_is_better=False),
    Metric("min", "Minutes", "pg"),
    Metric("gp", "Games Played", ""),
    Metric("fg_pct", "FG%", "%", percent=True),
    Metric("fg3_pct", "3P%", "%", percent=True),
    Metric("ft_pct", "FT%", "%", percent=True),
    Metric("ts_pct", "TS%", "%", percent=True),
    Metric("per", "PER", ""),
    Metric("usg_pct", "USG%", "%", percent=True),
]

METRICS_BY_KEY: Dict[str, Metric] = {m.key: m for m in METRICS}

# "a", "b", "tie", or None when the metric is unavailable for comparison.
Leader = Optional[str]


def compare_metric(metric: Metric, a: Optional[float], b: Optional[float]) -> Leader:
    """Return the winner for a single metric, or None if not comparable."""
    if a is None or b is None:
        return None  # unavailable for one or both — do not compare
    if a == b:
        return "tie"
    if metric.higher_is_better:
        return "a" if a > b else "b"
    return "a" if a < b else "b"


@dataclass
class MetricComparison:
    key: str
    label: str
    unit: str
    percent: bool
    a_value: Optional[float]
    b_value: Optional[float]
    leader: Leader  # "a" | "b" | "tie" | None (unavailable)
    available: bool


TOT = "TOT"

# Per-game or rate metrics aggregated as a games-played-weighted average.
_RATE_KEYS = ["min", "pts", "reb", "ast", "stl", "blk", "tov", "per", "ts_pct", "usg_pct"]

# Shooting percentages: rebuilt from total makes / attempts when available so a
# career split is weighted by volume, not by a flat average of season rates.
_SHOOTING = [
    ("fg_pct", "fgm", "fga"),
    ("fg3_pct", "fg3m", "fg3a"),
    ("ft_pct", "ftm", "fta"),
]

SeasonRow = Mapping[str, Optional[float]]


def collapse_seasons(rows: Sequence[SeasonRow]) -> List[SeasonRow]:
    """Reduce rows to one per season, preferring the multi-team ``TOT`` total.

    Each row must carry ``year_start`` and ``team``. When a player changed teams
    mid-season the data holds a ``TOT`` aggregate plus one row per team; only the
    aggregate is kept so totals are never double counted.
    """
    by_year: Dict[object, SeasonRow] = {}
    for r in rows:
        year = r.get("year_start")
        existing = by_year.get(year)
        if existing is None:
            by_year[year] = r
        elif r.get("team") == TOT and existing.get("team") != TOT:
            by_year[year] = r
    return list(by_year.values())


def _weighted_average(seasons: Sequence[SeasonRow], key: str) -> Optional[float]:
    num = 0.0
    den = 0.0
    for s in seasons:
        v = s.get(key)
        gp = s.get("gp")
        if v is not None and gp:
            num += float(v) * float(gp)
            den += float(gp)
    return num / den if den > 0 else None


def _sum(seasons: Sequence[SeasonRow], key: str) -> Optional[float]:
    total = 0.0
    seen = False
    for s in seasons:
        v = s.get(key)
        if v is not None:
            total += float(v)
            seen = True
    return total if seen else None


def _career_shooting(
    seasons: Sequence[SeasonRow], pct_key: str, makes_key: str, att_key: str
) -> Optional[float]:
    total_makes = 0.0
    total_att = 0.0
    have_volume = False
    for s in seasons:
        makes = s.get(makes_key)
        att = s.get(att_key)
        gp = s.get("gp")
        if makes is not None and att is not None and gp:
            total_makes += float(makes) * float(gp)
            total_att += float(att) * float(gp)
            have_volume = True
    if have_volume and total_att > 0:
        return total_makes / total_att
    # No attempt volume recorded — fall back to a GP-weighted average of the
    # recorded percentages, and leave it None if there is nothing to average.
    return _weighted_average(seasons, pct_key)


def aggregate_career(rows: Sequence[SeasonRow]) -> Dict[str, Optional[float]]:
    """Build a single career stat line from a player's season rows (one split).

    Rows are collapsed to one per season first. Counting/rate stats use a
    games-played-weighted average; ``gp`` is the career total; shooting splits
    are volume-weighted from makes/attempts. Missing stays missing — never 0.
    """
    seasons = collapse_seasons(rows)
    career: Dict[str, Optional[float]] = {}
    for key in _RATE_KEYS:
        career[key] = _weighted_average(seasons, key)
    career["gp"] = _sum(seasons, "gp")
    for pct_key, makes_key, att_key in _SHOOTING:
        career[pct_key] = _career_shooting(seasons, pct_key, makes_key, att_key)
    return career


def compare_players(
    stats_a: Dict[str, Optional[float]],
    stats_b: Dict[str, Optional[float]],
    metric_keys: Optional[List[str]] = None,
) -> List[MetricComparison]:
    """Compare two stat dictionaries metric-by-metric.

    ``available`` is False when either side lacks the metric; such metrics are
    surfaced (so the UI can show "—") but never scored.
    """
    keys = metric_keys or [m.key for m in METRICS]
    out: List[MetricComparison] = []
    for key in keys:
        metric = METRICS_BY_KEY.get(key)
        if metric is None:
            continue
        a = stats_a.get(key)
        b = stats_b.get(key)
        leader = compare_metric(metric, a, b)
        out.append(
            MetricComparison(
                key=metric.key,
                label=metric.label,
                unit=metric.unit,
                percent=metric.percent,
                a_value=a,
                b_value=b,
                leader=leader,
                available=leader is not None,
            )
        )
    return out
