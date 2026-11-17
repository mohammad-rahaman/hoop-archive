"""Player list/search/filter query logic.

Kept dialect-agnostic (works on both Postgres and the SQLite test DB). Name
search matches the normalized ``name_key`` so it is accent/punctuation
insensitive.
"""
from typing import List, Optional, Tuple

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.db.models import Player, PlayerSeasonStats, Season, SeasonType, Team
from app.etl.columns import normalize_name_key
from app.etl.enrich_nba import headshot_url
from app.schemas.player import (
    ComparisonPlayer,
    FilterOptions,
    MetricComparisonRow,
    PlayerComparison,
    PlayerDetail,
    PlayerListItem,
    SeasonStatRow,
)
from app.services.comparison import METRICS, aggregate_career, compare_players

TOT = "TOT"

_STAT_FIELDS = [
    "min", "pts", "reb", "ast", "stl", "blk", "tov",
    "fgm", "fga", "fg_pct", "fg3m", "fg3a", "fg3_pct",
    "ftm", "fta", "ft_pct", "per", "ts_pct", "usg_pct",
]

# Fields pulled per season to build a career comparison line.
_CAREER_FIELDS = _STAT_FIELDS


def _apply_filters(
    stmt,
    q: Optional[str],
    team: Optional[str],
    position: Optional[str],
    season: Optional[str] = None,
):
    if q:
        nq = normalize_name_key(q)
        if nq:
            stmt = stmt.where(Player.name_key.like(f"%{nq}%"))
    if position:
        stmt = stmt.where(Player.position == position)
    if team:
        team_exists = (
            select(PlayerSeasonStats.id)
            .join(Team, Team.id == PlayerSeasonStats.team_id)
            .where(
                PlayerSeasonStats.player_id == Player.id,
                func.upper(Team.abbreviation) == team.upper(),
            )
            .exists()
        )
        stmt = stmt.where(team_exists)
    if season:
        # Players with at least one stat line (any split) in that season.
        season_exists = (
            select(PlayerSeasonStats.id)
            .join(Season, Season.id == PlayerSeasonStats.season_id)
            .where(
                PlayerSeasonStats.player_id == Player.id,
                Season.label == season,
            )
            .exists()
        )
        stmt = stmt.where(season_exists)
    return stmt


def list_players(
    db: Session,
    q: Optional[str] = None,
    team: Optional[str] = None,
    position: Optional[str] = None,
    page: int = 1,
    page_size: int = 25,
    season: Optional[str] = None,
) -> Tuple[int, List[PlayerListItem]]:
    base = _apply_filters(select(Player.id), q, team, position, season)

    total = db.scalar(select(func.count()).select_from(base.subquery())) or 0

    page_stmt = (
        _apply_filters(select(Player), q, team, position, season)
        .order_by(Player.full_name.asc(), Player.id.asc())
        .limit(page_size)
        .offset((page - 1) * page_size)
    )
    players = db.scalars(page_stmt).all()
    if not players:
        return total, []

    ids = [p.id for p in players]

    # One pass over this page's stat rows to derive aggregates.
    rows = db.execute(
        select(
            PlayerSeasonStats.player_id,
            Season.year_start,
            Season.label,
            Team.abbreviation,
        )
        .join(Season, Season.id == PlayerSeasonStats.season_id)
        .join(Team, Team.id == PlayerSeasonStats.team_id)
        .where(PlayerSeasonStats.player_id.in_(ids))
    ).all()

    agg: dict = {pid: {"seasons": set(), "teams": set(), "latest": (None, None)} for pid in ids}
    for pid, year_start, label, abbr in rows:
        a = agg[pid]
        a["seasons"].add(label)
        if abbr and abbr != TOT:
            a["teams"].add(abbr)
            cur_year, _ = a["latest"]
            if cur_year is None or (year_start is not None and year_start >= cur_year):
                a["latest"] = (year_start, abbr)
        # Track latest season label regardless of team.
        a.setdefault("latest_label", (None, None))
        ly, _ = a["latest_label"]
        if ly is None or (year_start is not None and year_start >= ly):
            a["latest_label"] = (year_start, label)

    items: List[PlayerListItem] = []
    for p in players:
        a = agg[p.id]
        # derive first/last year from season labels' start years
        season_years = sorted(
            {int(lbl.split("-")[0]) for lbl in a["seasons"] if lbl and lbl[:4].isdigit()}
        )
        items.append(
            PlayerListItem(
                id=p.id,
                full_name=p.full_name,
                position=p.position,
                latest_team=a["latest"][1],
                teams=sorted(a["teams"]),
                season_count=len(a["seasons"]),
                first_year=season_years[0] if season_years else None,
                last_year=season_years[-1] if season_years else None,
                latest_season=a.get("latest_label", (None, None))[1],
                image_url=headshot_url(p.external_ids),
            )
        )
    return total, items


def get_player_detail(db: Session, player_id: int) -> Optional[PlayerDetail]:
    player = db.get(Player, player_id)
    if player is None:
        return None

    rows = db.execute(
        select(PlayerSeasonStats, Season, Team)
        .join(Season, Season.id == PlayerSeasonStats.season_id)
        .join(Team, Team.id == PlayerSeasonStats.team_id)
        .where(PlayerSeasonStats.player_id == player_id)
        # Most-recent season first; regular before playoff; TOT aggregate before
        # individual teams within a season.
        .order_by(
            Season.year_start.desc(),
            # Regular season before playoffs (the enum string sorts the other
            # way alphabetically, so order explicitly).
            (PlayerSeasonStats.season_type == SeasonType.PLAYOFF).asc(),
            (Team.abbreviation != TOT).asc(),
            Team.abbreviation.asc(),
        )
    ).all()

    seasons: List[SeasonStatRow] = []
    team_set = set()
    years = set()
    has_playoffs = False
    for stat, season, team in rows:
        if team.abbreviation != TOT:
            team_set.add(team.abbreviation)
        years.add(season.year_start)
        if stat.season_type == SeasonType.PLAYOFF:
            has_playoffs = True
        row = SeasonStatRow(
            season=season.label,
            year_start=season.year_start,
            season_type=stat.season_type.value,
            team=team.abbreviation,
            stat_mode=stat.stat_mode.value,
            source=stat.source,
            gp=stat.gp,
            **{f: getattr(stat, f) for f in _STAT_FIELDS},
        )
        seasons.append(row)

    return PlayerDetail(
        id=player.id,
        full_name=player.full_name,
        position=player.position,
        jersey_number=player.jersey_number,
        teams=sorted(team_set),
        first_year=min(years) if years else None,
        last_year=max(years) if years else None,
        season_count=len({s.season for s in seasons}),
        has_playoffs=has_playoffs,
        image_url=headshot_url(player.external_ids),
        seasons=seasons,
    )


def _career_season_rows(
    db: Session,
    player_id: int,
    season_type: SeasonType,
    season: Optional[str] = None,
):
    """Season rows (one per team-stint) for a player in one split, as dicts
    ready for :func:`aggregate_career`. With ``season`` set, only that season's
    rows are returned, so the "career" line becomes that single season."""
    stmt = (
        select(PlayerSeasonStats, Season.year_start, Team.abbreviation)
        .join(Season, Season.id == PlayerSeasonStats.season_id)
        .join(Team, Team.id == PlayerSeasonStats.team_id)
        .where(
            PlayerSeasonStats.player_id == player_id,
            PlayerSeasonStats.season_type == season_type,
        )
    )
    if season:
        stmt = stmt.where(Season.label == season)
    rows = db.execute(stmt).all()
    out = []
    for stat, year_start, abbr in rows:
        row = {"year_start": year_start, "team": abbr, "gp": stat.gp}
        for f in _CAREER_FIELDS:
            row[f] = getattr(stat, f)
        out.append(row)
    return out


def _season_team(
    db: Session, player_id: int, season: str, season_type: SeasonType
) -> Optional[str]:
    """Team for one season in one split: "TOT" when the player was traded."""
    abbrs = db.scalars(
        select(Team.abbreviation)
        .join(PlayerSeasonStats, PlayerSeasonStats.team_id == Team.id)
        .join(Season, Season.id == PlayerSeasonStats.season_id)
        .where(
            PlayerSeasonStats.player_id == player_id,
            PlayerSeasonStats.season_type == season_type,
            Season.label == season,
        )
    ).all()
    if not abbrs:
        return None
    return TOT if TOT in abbrs else abbrs[0]


def _comparison_player(
    db: Session,
    player_id: int,
    season: Optional[str] = None,
    season_type: SeasonType = SeasonType.REGULAR,
):
    player = db.get(Player, player_id)
    if player is None:
        return None
    rows = db.execute(
        select(Season.year_start, Team.abbreviation)
        .join(PlayerSeasonStats, PlayerSeasonStats.season_id == Season.id)
        .join(Team, Team.id == PlayerSeasonStats.team_id)
        .where(PlayerSeasonStats.player_id == player_id)
    ).all()
    years = {y for y, _ in rows if y is not None}
    teams = sorted({a for _, a in rows if a and a != TOT})
    return ComparisonPlayer(
        id=player.id,
        full_name=player.full_name,
        position=player.position,
        teams=teams,
        first_year=min(years) if years else None,
        last_year=max(years) if years else None,
        season_count=len({y for y, _ in rows}),
        image_url=headshot_url(player.external_ids),
        season=season,
        season_team=(
            _season_team(db, player_id, season, season_type) if season else None
        ),
    )


def get_comparison(
    db: Session,
    id_a: int,
    id_b: int,
    season_type: SeasonType,
    a_season: Optional[str] = None,
    b_season: Optional[str] = None,
) -> Optional[PlayerComparison]:
    """Compare two players for one split, or None if either id is unknown.

    Each side is a career line by default, or a single season when its
    ``*_season`` label is given (e.g. one player's 2015-16 against another's
    2020-21). A season with no rows in this split compares as unavailable,
    never as zero."""
    a = _comparison_player(db, id_a, a_season, season_type)
    b = _comparison_player(db, id_b, b_season, season_type)
    if a is None or b is None:
        return None

    stats_a = aggregate_career(_career_season_rows(db, id_a, season_type, a_season))
    stats_b = aggregate_career(_career_season_rows(db, id_b, season_type, b_season))
    keys = [m.key for m in METRICS]
    comparisons = compare_players(stats_a, stats_b, keys)

    metrics = [
        MetricComparisonRow(
            key=c.key,
            label=c.label,
            unit=c.unit,
            percent=c.percent,
            a_value=c.a_value,
            b_value=c.b_value,
            leader=c.leader,
            available=c.available,
        )
        for c in comparisons
    ]
    a_wins = sum(1 for c in comparisons if c.leader == "a")
    b_wins = sum(1 for c in comparisons if c.leader == "b")
    ties = sum(1 for c in comparisons if c.leader == "tie")
    return PlayerComparison(
        season_type=season_type.value,
        a=a,
        b=b,
        metrics=metrics,
        a_wins=a_wins,
        b_wins=b_wins,
        ties=ties,
    )


def filter_options(db: Session) -> FilterOptions:
    teams = db.scalars(
        select(Team.abbreviation).where(Team.abbreviation != TOT).order_by(Team.abbreviation)
    ).all()
    positions = db.scalars(
        select(Player.position)
        .where(Player.position.is_not(None))
        .distinct()
        .order_by(Player.position)
    ).all()
    seasons = db.scalars(
        select(Season.label)
        .where(select(PlayerSeasonStats.id).where(PlayerSeasonStats.season_id == Season.id).exists())
        .order_by(Season.year_start.desc())
    ).all()
    return FilterOptions(
        teams=list(teams),
        positions=[p for p in positions if p],
        seasons=list(seasons),
    )
