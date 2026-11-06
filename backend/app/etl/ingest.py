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
from typing import Dict, Optional

from sqlalchemy import select
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


def _get_or_create_team(session: Session, cache: Dict[str, Team], abbr: Optional[str], res: IngestResult) -> Team:
    key = (abbr or "").strip().upper() or UNKNOWN_TEAM
    if key in cache:
        return cache[key]
    team = session.scalar(select(Team).where(Team.abbreviation == key))
    if team is None:
        team = Team(abbreviation=key, name=None if key == UNKNOWN_TEAM else None)
        session.add(team)
        session.flush()
        res.teams_created += 1
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
) -> IngestResult:
    res = IngestResult()
    started = datetime.now(timezone.utc)

    team_cache: Dict[str, Team] = {}
    season_cache: Dict[str, Season] = {}
    player_cache: Dict[str, Player] = {}

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
            parsed = C.parse_season(getval(row, "season"))
            if not name or parsed is None:
                res.rows_skipped += 1
                continue
            label, year_start = parsed

            team = _get_or_create_team(session, team_cache, getval(row, "team"), res)
            season = _get_or_create_season(session, season_cache, label, year_start, res)
            player = _get_or_create_player(
                session, player_cache, str(name),
                getval(row, "position"), getval(row, "jersey_number"), res,
            )
            season_type = SeasonType(C.parse_season_type(getval(row, "season_type")))

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

            stat.stat_mode = stat_mode
            stat.source = source
            stat.gp = coerce_int(getval(row, "gp"))
            for fld in _STAT_FLOAT_FIELDS:
                setattr(stat, fld, coerce_float(getval(row, fld)))

            if is_new:
                res.stats_inserted += 1
            else:
                res.stats_updated += 1

            if res.rows_read % batch_size == 0:
                session.flush()

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
    parser.add_argument("--audit-only", action="store_true", help="Print the audit report and exit without writing.")
    args = parser.parse_args()

    report = audit_csv(args.csv, source_label=args.csv)
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
            source_label=args.csv,
        )
    print(result.summary())


if __name__ == "__main__":
    main()
