"""Player comparison calculations.

Rules (from the PDP):
* Never treat a missing (None) value as 0.
* Never compare a metric that is unavailable for either player.
* Most metrics: higher is better. Turnovers: lower is better.
"""
from dataclasses import dataclass
from typing import Dict, List, Optional


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
