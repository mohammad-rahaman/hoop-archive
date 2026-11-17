"""Idempotent CSV ingestion.

Running the same file twice updates existing rows instead of creating duplicates,
because every dimension (team/season/player) and the fact table
(player_season_stats) is keyed on a stable natural key. Missing statistics are
stored as NULL — never 0.

CLI:
    python -m app.etl.ingest --csv backend/data/sample/sample_nba_synthetic.csv
    python -m app.etl.ingest --csv path/to/kaggle.csv --stat-mode per_game --audit-only
"""
import argparse
import csv
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Dict, List, Optional, Set

from sqlalchemy import delete, select
from sqlalchemy.orm import Session

from app.db.models import (
    Player,
    PlayerSeasonStats,
    Season,
    SeasonType,
    StatMode,
    SyncMetadata,
    Team,
)
from app.etl import columns as C
from app.etl.validate import audit_csv, coerce_float, coerce_int

UNKNOWN_TEAM = "UNK"


@dataclass
class IngestResult:
    rows_read: int = 0
    rows_skipped: int = 0
    stats_inserted: int = 0
    stats_updated: int = 0
    players_created: int = 0
    teams_created: int = 0
    seasons_created: int = 0
    warnings: list = field(default_factory=list)

    def summary(self) -> str:
        return (
            f"Ingest complete: read={self.rows_read} skipped={self.rows_skipped} "
            f"stats(inserted={self.stats_inserted}, updated={self.stats_updated}) "
            f"players+={self.players_created} teams+={self.teams_created} "
            f"seasons+={self.seasons_created}"
        )


def _get_or_create_team(
    session: Session,
    cache: Dict[str, Team],
    abbr: Optional[str],
    res: IngestResult,
    team_name: Optional[str] = None,
) -> Team:
    key = (abbr or "").strip().upper() or UNKNOWN_TEAM
    cleaned_name = team_name.strip() if (team_name and key != UNKNOWN_TEAM) else None
    if key in cache:
        team = cache[key]
        if cleaned_name and not team.name:
            team.name = cleaned_name
        return team
    team = session.scalar(select(Team).where(Team.abbreviation == key))
    if team is None:
        team = Team(abbreviation=key, name=cleaned_name)
        session.add(team)
        session.flush()
        res.teams_created += 1
    elif cleaned_name and not team.name:
        team.name = cleaned_name
    cache[key] = team
    return team


def _get_or_create_season(session: Session, cache: Dict[str, Season], label: str, year_start: int, res: IngestResult) -> Season:
    if label in cache:
        return cache[label]
    season = session.scalar(select(Season).where(Season.label == label))
    if season is None:
        season = Season(label=label, year_start=year_start)
        session.add(season)
        session.flush()
        res.seasons_created += 1
    cache[label] = season
    return season


def _get_or_create_player(
    session: Session, cache: Dict[str, Player], full_name: str,
    position: Optional[str], jersey: Optional[str], res: IngestResult,
) -> Player:
    name_key = C.normalize_name_key(full_name)
    if name_key in cache:
        player = cache[name_key]
    else:
        player = session.scalar(select(Player).where(Player.name_key == name_key))
        if player is None:
            player = Player(name_key=name_key, full_name=full_name.strip())
            session.add(player)
            session.flush()
            res.players_created += 1
        cache[name_key] = player
    # Backfill attributes only when currently unknown (don't clobber good data).
    if position and not player.position:
        player.position = position.strip()
    if jersey and not player.jersey_number:
        player.jersey_number = str(jersey).strip()
    return player


_STAT_FLOAT_FIELDS = [
    "min", "pts", "reb", "ast", "stl", "blk", "tov",
    "fgm", "fga", "fg_pct", "fg3m", "fg3a", "fg3_pct",
    "ftm", "fta", "ft_pct", "per", "ts_pct", "usg_pct",
]


def ingest_csv(
    session: Session,
    path: str,
    stat_mode: StatMode = StatMode.PER_GAME,
    source: str = "kaggle_csv",
    source_label: Optional[str] = None,
    batch_size: int = 500,
    bare_year_is_end: bool = False,
    replace_existing: bool = False,
) -> IngestResult:
    res = IngestResult()
    started = datetime.now(timezone.utc)

    if replace_existing:
        session.execute(delete(PlayerSeasonStats))
        session.execute(delete(Player))
        session.execute(delete(Season))
        session.execute(delete(Team))
        session.execute(delete(SyncMetadata))
        session.flush()

    team_cache: Dict[str, Team] = {}
    season_cache: Dict[str, Season] = {}
    player_cache: Dict[str, Player] = {}
    stat_cache: Dict[tuple, PlayerSeasonStats] = {}
    new_player_ids: Set[int] = set()
    # player_id -> position -> [total_gp_weight, latest_year_start]
    pos_candidates: Dict[int, Dict[str, List[int]]] = {}
    resolve_pos_players: Dict[int, Player] = {}

    with open(path, newline="", encoding="utf-8-sig") as f:
        reader = csv.DictReader(f)
        headers = list(reader.fieldnames or [])
        cmap = C.build_column_map(headers)
        missing = [r for r in C.REQUIRED_FIELDS if r not in cmap]
        if missing:
            raise ValueError(
                f"CSV missing required field(s) {missing}. Headers seen: {headers}"
            )

        def getval(row, canon):
            col = cmap.get(canon)
            if not col:
                return None
            v = row.get(col)
            return v if (v is not None and str(v).strip() != "") else None

        for row in reader:
            res.rows_read += 1

            name = getval(row, "player_name")
            parsed = C.parse_season(getval(row, "season"), bare_year_is_end=bare_year_is_end)
            if not name or parsed is None:
                res.rows_skipped += 1
                continue
            label, year_start = parsed

            team = _get_or_create_team(
                session, team_cache, getval(row, "team"), res,
                team_name=getval(row, "team_name"),
            )
            season = _get_or_create_season(session, season_cache, label, year_start, res)
            players_before = res.players_created
            player = _get_or_create_player(
                session, player_cache, str(name),
                None, getval(row, "jersey_number"), res,
            )
            if res.players_created > players_before:
                new_player_ids.add(player.id)
            if not player.position:
                resolve_pos_players[player.id] = player

            season_type = SeasonType(C.parse_season_type(getval(row, "season_type")))
            stat_key = (player.id, season.id, team.id, season_type)

            stat = stat_cache.get(stat_key)
            if stat is None and player.id not in new_player_ids:
                stat = session.scalar(
                    select(PlayerSeasonStats).where(
                        PlayerSeasonStats.player_id == player.id,
                        PlayerSeasonStats.season_id == season.id,
                        PlayerSeasonStats.team_id == team.id,
                        PlayerSeasonStats.season_type == season_type,
                    )
                )
                if stat is not None:
                    stat_cache[stat_key] = stat

            is_new = stat is None
            if is_new:
                stat = PlayerSeasonStats(
                    player_id=player.id, season_id=season.id, team_id=team.id,
                    season_type=season_type,
                )
                session.add(stat)
                stat_cache[stat_key] = stat

            gp_val = coerce_int(getval(row, "gp"))
            stat.stat_mode = stat_mode
            stat.source = source
            stat.gp = gp_val
            for fld in _STAT_FLOAT_FIELDS:
                setattr(stat, fld, coerce_float(getval(row, fld)))

            if is_new:
                res.stats_inserted += 1
                pos = getval(row, "position")
                if pos and player.id in resolve_pos_players:
                    p_clean = pos.strip()
                    weight = max(gp_val or 1, 1)
                    entry = pos_candidates.setdefault(player.id, {}).setdefault(p_clean, [0, year_start])
                    entry[0] += weight
                    entry[1] = max(entry[1], year_start)
            else:
                res.stats_updated += 1

            if res.rows_read % batch_size == 0:
                session.flush()

    for pid, player in resolve_pos_players.items():
        candidates = pos_candidates.get(pid)
        if candidates and not player.position:
            best_pos = max(candidates.items(), key=lambda kv: (kv[1][0], kv[1][1]))[0]
            player.position = best_pos

    meta = SyncMetadata(
        provider=source,
        source_label=source_label or path,
        rows_ingested=res.stats_inserted,
        rows_updated=res.stats_updated,
        status="success",
        notes=res.summary(),
        started_at=started,
        finished_at=datetime.now(timezone.utc),
    )
    session.add(meta)
    session.commit()
    return res


def main() -> None:
    parser = argparse.ArgumentParser(description="Ingest an NBA stats CSV into Hoop Archive.")
    parser.add_argument("--csv", required=True, help="Path to the CSV file.")
    parser.add_argument("--stat-mode", choices=[m.value for m in StatMode], default=StatMode.PER_GAME.value)
    parser.add_argument("--source", default="kaggle_csv")
    parser.add_argument("--source-label", default=None, help="Optional display label stored in sync_metadata.")
    parser.add_argument(
        "--year-is-end",
        action="store_true",
        help="Treat bare 4-digit years (e.g. 1991 or 1991.0) as the season end year (1990-91).",
    )
    parser.add_argument(
        "--replace",
        action="store_true",
        help="Clear existing database rows before ingesting.",
    )
    parser.add_argument("--audit-only", action="store_true", help="Print the audit report and exit without writing.")
    args = parser.parse_args()

    label = args.source_label or args.csv
    report = audit_csv(args.csv, source_label=label, bare_year_is_end=args.year_is_end)
    print(report.summary())
    if args.audit_only:
        return
    if report.missing_required:
        raise SystemExit(f"Refusing to ingest: missing required fields {report.missing_required}")

    from app.db.session import SessionLocal

    with SessionLocal() as session:
        result = ingest_csv(
            session, args.csv,
            stat_mode=StatMode(args.stat_mode),
            source=args.source,
            source_label=label,
            bare_year_is_end=args.year_is_end,
            replace_existing=args.replace,
        )
    print(result.summary())


if __name__ == "__main__":
    main()
