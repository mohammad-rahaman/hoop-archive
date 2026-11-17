"""Dataset inspection / validation (the 'first, inspect the dataset' step).

Produces an audit report and provides value-coercion helpers used by ingestion.
Coercion never turns a missing value into 0 — blanks/NaN become ``None``.
"""
import csv
import math
from dataclasses import dataclass, field
from typing import Dict, List, Optional

from app.etl import columns as C

_MISSING_TOKENS = {"", "na", "n/a", "nan", "none", "null", "-"}


def coerce_float(raw) -> Optional[float]:
    if raw is None:
        return None
    s = str(raw).strip().replace("%", "")
    if s.lower() in _MISSING_TOKENS:
        return None
    try:
        v = float(s)
    except ValueError:
        return None
    if math.isnan(v) or math.isinf(v):
        return None
    return v


def coerce_int(raw) -> Optional[int]:
    v = coerce_float(raw)
    return int(round(v)) if v is not None else None


@dataclass
class AuditReport:
    source_label: str
    total_rows: int = 0
    headers: List[str] = field(default_factory=list)
    column_map: Dict[str, str] = field(default_factory=dict)
    unmapped_headers: List[str] = field(default_factory=list)
    missing_required: List[str] = field(default_factory=list)
    distinct_players: int = 0
    distinct_teams: int = 0
    season_range: Optional[tuple] = None
    unparseable_seasons: int = 0
    duplicate_natural_keys: int = 0
    null_counts: Dict[str, int] = field(default_factory=dict)
    warnings: List[str] = field(default_factory=list)

    def summary(self) -> str:
        lines = [
            f"Dataset audit: {self.source_label}",
            f"  rows:              {self.total_rows}",
            f"  columns:           {len(self.headers)}",
            f"  mapped fields:     {len(self.column_map)} -> {sorted(self.column_map)}",
            f"  unmapped headers:  {self.unmapped_headers or 'none'}",
            f"  missing required:  {self.missing_required or 'none'}",
            f"  distinct players:  {self.distinct_players}",
            f"  distinct teams:    {self.distinct_teams}",
            f"  season range:      {self.season_range}",
            f"  unparseable seasons: {self.unparseable_seasons}",
            f"  duplicate (player,season,team,type) keys: {self.duplicate_natural_keys}",
        ]
        if self.null_counts:
            top = sorted(self.null_counts.items(), key=lambda kv: -kv[1])[:8]
            lines.append(f"  highest null counts: {top}")
        for w in self.warnings:
            lines.append(f"  WARNING: {w}")
        return "\n".join(lines)


def audit_csv(
    path: str,
    source_label: Optional[str] = None,
    sample_limit: Optional[int] = None,
    bare_year_is_end: bool = False,
) -> AuditReport:
    """Read the CSV once and compute an audit report."""
    report = AuditReport(source_label=source_label or path)
    with open(path, newline="", encoding="utf-8-sig") as f:
        reader = csv.DictReader(f)
        report.headers = list(reader.fieldnames or [])
        report.column_map = C.build_column_map(report.headers)
        report.unmapped_headers = C.unmapped_headers(report.headers, report.column_map)
        report.missing_required = [r for r in C.REQUIRED_FIELDS if r not in report.column_map]

        players = set()
        teams = set()
        seen_keys = set()
        null_counts: Dict[str, int] = {canon: 0 for canon in report.column_map}
        min_year = None
        max_year = None

        for i, row in enumerate(reader):
            if sample_limit is not None and i >= sample_limit:
                break
            report.total_rows += 1

            def val(canon):
                col = report.column_map.get(canon)
                return row.get(col) if col else None

            for canon, col in report.column_map.items():
                raw = row.get(col)
                if raw is None or str(raw).strip().lower() in _MISSING_TOKENS:
                    null_counts[canon] += 1

            name = val("player_name")
            if name and str(name).strip():
                players.add(C.normalize_name_key(str(name)))

            team = val("team")
            if team and str(team).strip():
                teams.add(str(team).strip().upper())

            parsed = C.parse_season(val("season"), bare_year_is_end=bare_year_is_end)
            if parsed is None:
                report.unparseable_seasons += 1
            else:
                _, ys = parsed
                min_year = ys if min_year is None else min(min_year, ys)
                max_year = ys if max_year is None else max(max_year, ys)

            stype = C.parse_season_type(val("season_type"))
            nk = (
                C.normalize_name_key(str(name or "")),
                parsed[0] if parsed else None,
                (str(team).strip().upper() if team else None),
                stype,
            )
            if nk in seen_keys:
                report.duplicate_natural_keys += 1
            else:
                seen_keys.add(nk)

        report.distinct_players = len(players)
        report.distinct_teams = len(teams)
        report.season_range = (min_year, max_year) if min_year is not None else None
        report.null_counts = {k: v for k, v in null_counts.items() if v}

    if report.missing_required:
        report.warnings.append(
            f"required field(s) missing: {report.missing_required}; rows cannot be ingested"
        )
    if report.duplicate_natural_keys:
        report.warnings.append(
            f"{report.duplicate_natural_keys} duplicate natural keys — ingestion is idempotent "
            f"and will upsert these (last value wins)"
        )
    return report
