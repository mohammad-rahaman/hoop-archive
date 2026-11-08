"""Provider sync: turn Sportradar seasonal statistics into stored stat rows.

Guarantees carried from the PDP:
* Missing statistics are never fabricated or treated as 0 — an absent field maps
  to NULL.
* Regular season and playoffs stay distinct (Sportradar ``REG`` vs ``PST``).
* Idempotent upserts keyed on (player, season, team, season_type), so a repeat
  sync updates rows instead of duplicating them.
* When Sportradar is not configured the sync is recorded as *skipped* and the app
  keeps serving existing historical/sample data.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Sequence, Tuple

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import settings
from app.db.models import PlayerSeasonStats, SeasonType, StatMode, SyncMetadata
from app.etl.ingest import (
    IngestResult,
    _get_or_create_player,
    _get_or_create_season,
    _get_or_create_team,
)
from app.etl.validate import coerce_float, coerce_int
from app.providers.sportradar import SportradarClient, SportradarNotConfigured

PROVIDER = "sportradar"

# Sportradar "average" field -> our canonical stat field. Advanced metrics we do
# not get a faithful value for (e.g. PER, USG%) are intentionally left out so we
# never store a fabricated number.
_AVERAGE_MAP: Dict[str, str] = {
    "minutes": "min",
    "points": "pts",
    "rebounds": "reb",
    "assists": "ast",
    "steals": "stl",
    "blocks": "blk",
    "turnovers": "tov",
    "field_goals_made": "fgm",
    "field_goals_att": "fga",
    "field_goals_pct": "fg_pct",
    "three_points_made": "fg3m",
    "three_points_att": "fg3a",
    "three_points_pct": "fg3_pct",
    "free_throws_made": "ftm",
    "free_throws_att": "fta",
    "free_throws_pct": "ft_pct",
    "true_shooting_pct": "ts_pct",
    "usage_pct": "usg_pct",
}

_FLOAT_FIELDS = list(_AVERAGE_MAP.values())


@dataclass
class SyncResult:
    provider: str = PROVIDER
    status: str = "success"  # success | skipped | error
    teams_processed: int = 0
    rows_inserted: int = 0
    rows_updated: int = 0
    players_created: int = 0
    notes: str = ""
    warnings: List[str] = field(default_factory=list)

    def summary(self) -> str:
        return (
            f"{self.provider} sync {self.status}: teams={self.teams_processed} "
            f"inserted={self.rows_inserted} updated={self.rows_updated} "
            f"players+={self.players_created}"
        )


def _season_label(year_start: int) -> str:
    return f"{year_start}-{str((year_start + 1) % 100).zfill(2)}"


def _season_type(code: Optional[str]) -> SeasonType:
    # REG -> regular; anything else (PST/PLA/…) counts as playoffs.
    return SeasonType.REGULAR if (code or "").upper() == "REG" else SeasonType.PLAYOFF


def _full_name(player: Dict[str, Any]) -> Optional[str]:
    name = player.get("full_name")
    if name and str(name).strip():
        return str(name).strip()
    first = (player.get("first_name") or "").strip()
    last = (player.get("last_name") or "").strip()
    combined = f"{first} {last}".strip()
    return combined or None


def normalize_seasonal_statistics(payload: Dict[str, Any]) -> List[Dict[str, Any]]:
    """Map one Sportradar seasonal-statistics payload to canonical stat rows.

    Returns a list of dicts (one per player). Any missing value is ``None``.
    """
    season = payload.get("season") or {}
    year = season.get("year")
    stype = _season_type(season.get("type"))
    team = payload.get("team") or {}
    team_abbr = team.get("alias") or team.get("abbreviation")
    # Sportradar nests the roster under ``team.players``; accept a top-level
    # ``players`` list as well.
    players = team.get("players") or payload.get("players") or []

    rows: List[Dict[str, Any]] = []
    if year is None:
        return rows

    for player in players:
        name = _full_name(player)
        if not name:
            continue
        average = player.get("average") or {}
        total = player.get("total") or {}

        row: Dict[str, Any] = {
            "player_name": name,
            "year_start": int(year),
            "season_label": _season_label(int(year)),
            "season_type": stype,
            "team": team_abbr,
            "position": player.get("primary_position") or player.get("position"),
            "jersey_number": player.get("jersey_number"),
            "external_id": player.get("id"),
            # Games played is a season total, not an average.
            "gp": coerce_int(total.get("games_played")),
        }
        for sr_key, canon in _AVERAGE_MAP.items():
            row[canon] = coerce_float(average.get(sr_key))
        rows.append(row)
    return rows


def _upsert_rows(
    session: Session,
    rows: Sequence[Dict[str, Any]],
    source_label: str,
    res: IngestResult,
) -> None:
    team_cache: Dict[str, Any] = {}
    season_cache: Dict[str, Any] = {}
    player_cache: Dict[str, Any] = {}

    for row in rows:
        res.rows_read += 1
        team = _get_or_create_team(session, team_cache, row.get("team"), res)
        season = _get_or_create_season(
            session, season_cache, row["season_label"], row["year_start"], res
        )
        player = _get_or_create_player(
            session, player_cache, row["player_name"],
            row.get("position"), row.get("jersey_number"), res,
        )
        # Record the provider id without clobbering existing ids.
        ext = row.get("external_id")
        if ext:
            ids = dict(player.external_ids or {})
            if ids.get(PROVIDER) != ext:
                ids[PROVIDER] = ext
                player.external_ids = ids

        season_type: SeasonType = row["season_type"]
        stat = session.scalar(
            select(PlayerSeasonStats).where(
                PlayerSeasonStats.player_id == player.id,
                PlayerSeasonStats.season_id == season.id,
                PlayerSeasonStats.team_id == team.id,
                PlayerSeasonStats.season_type == season_type,
            )
        )
        is_new = stat is None
        if is_new:
            stat = PlayerSeasonStats(
                player_id=player.id, season_id=season.id, team_id=team.id,
                season_type=season_type,
            )
            session.add(stat)

        stat.stat_mode = StatMode.PER_GAME
        stat.source = PROVIDER
        stat.gp = row.get("gp")
        for fld in _FLOAT_FIELDS:
            setattr(stat, fld, row.get(fld))

        if is_new:
            res.stats_inserted += 1
        else:
            res.stats_updated += 1


def _record_sync(
    session: Session,
    *,
    status: str,
    source_label: str,
    started: datetime,
    rows_inserted: int = 0,
    rows_updated: int = 0,
    notes: str = "",
) -> None:
    session.add(
        SyncMetadata(
            provider=PROVIDER,
            source_label=source_label,
            rows_ingested=rows_inserted,
            rows_updated=rows_updated,
            status=status,
            notes=notes[:1000] if notes else None,
            started_at=started,
            finished_at=datetime.now(timezone.utc),
        )
    )
    session.commit()


def sync_from_payloads(
    session: Session,
    payloads: Sequence[Dict[str, Any]],
    source_label: Optional[str] = None,
) -> SyncResult:
    """Upsert a set of already-fetched Sportradar payloads. Network-free; this is
    the core used by both the live sync and tests."""
    started = datetime.now(timezone.utc)
    label = source_label or _default_source_label()
    res = IngestResult()
    teams = 0
    for payload in payloads:
        rows = normalize_seasonal_statistics(payload)
        if rows:
            teams += 1
        _upsert_rows(session, rows, label, res)

    result = SyncResult(
        status="success",
        teams_processed=teams,
        rows_inserted=res.stats_inserted,
        rows_updated=res.stats_updated,
        players_created=res.players_created,
        notes=res.summary(),
    )
    _record_sync(
        session,
        status="success",
        source_label=label,
        started=started,
        rows_inserted=res.stats_inserted,
        rows_updated=res.stats_updated,
        notes=result.summary(),
    )
    return result


def _default_source_label() -> str:
    return f"Sportradar NBA v8 ({settings.sportradar_access_level})"


def _specs_from_settings(
    season_year: Optional[int],
) -> List[Tuple[int, str, str]]:
    year = season_year if season_year is not None else settings.sync_season_year
    if year is None:
        return []
    # Regular-season refresh for each configured team. Playoffs can be added by
    # callers passing explicit specs.
    return [(year, "REG", team_id) for team_id in settings.sync_team_id_list]


def run_sportradar_sync(
    session: Session,
    client: Optional[SportradarClient] = None,
    specs: Optional[Sequence[Tuple[int, str, str]]] = None,
    season_year: Optional[int] = None,
) -> SyncResult:
    """Fetch and store Sportradar data. Falls back to a recorded *skipped* run
    (no exception) when the provider is unconfigured or nothing is targeted."""
    started = datetime.now(timezone.utc)
    client = client or SportradarClient()
    label = _default_source_label()

    if not client.configured:
        _record_sync(
            session,
            status="skipped",
            source_label=label,
            started=started,
            notes="Sportradar API key not configured; served existing data.",
        )
        return SyncResult(
            status="skipped",
            notes="Sportradar not configured; no live data fetched.",
        )

    targets = list(specs) if specs is not None else _specs_from_settings(season_year)
    if not targets:
        _record_sync(
            session,
            status="skipped",
            source_label=label,
            started=started,
            notes="No season/team targets configured for sync.",
        )
        return SyncResult(
            status="skipped",
            notes="No sync targets configured (set SYNC_SEASON_YEAR and SYNC_TEAM_IDS).",
        )

    try:
        payloads = [
            client.seasonal_team_statistics(year, stype, team_id)
            for (year, stype, team_id) in targets
        ]
    except SportradarNotConfigured:
        _record_sync(
            session,
            status="skipped",
            source_label=label,
            started=started,
            notes="Sportradar API key not configured; served existing data.",
        )
        return SyncResult(status="skipped", notes="Sportradar not configured.")
    except Exception as exc:  # provider/network error — record and surface safely
        _record_sync(
            session,
            status="error",
            source_label=label,
            started=started,
            notes=f"Sync failed: {exc}",
        )
        return SyncResult(status="error", notes=f"Sportradar sync failed: {exc}")

    return sync_from_payloads(session, payloads, source_label=label)
