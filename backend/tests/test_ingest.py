from sqlalchemy import func, select

from app.db.models import Player, PlayerSeasonStats, Season, SeasonType, Team
from app.etl.ingest import ingest_csv


def _counts(session):
    return {
        "players": session.scalar(select(func.count()).select_from(Player)),
        "teams": session.scalar(select(func.count()).select_from(Team)),
        "seasons": session.scalar(select(func.count()).select_from(Season)),
        "stats": session.scalar(select(func.count()).select_from(PlayerSeasonStats)),
    }


def test_ingest_then_reingest_is_idempotent(db_session, sample_csv):
    r1 = ingest_csv(db_session, sample_csv)
    assert r1.stats_inserted == 16
    assert r1.stats_updated == 0
    first = _counts(db_session)

    r2 = ingest_csv(db_session, sample_csv)
    assert r2.stats_inserted == 0
    assert r2.stats_updated == 16
    assert _counts(db_session) == first  # no duplicates created


def test_missing_stats_stored_as_null(db_session, sample_csv):
    ingest_csv(db_session, sample_csv)
    player = db_session.scalar(select(Player).where(Player.name_key == "kenji sato"))
    stat = db_session.scalar(
        select(PlayerSeasonStats).where(PlayerSeasonStats.player_id == player.id)
    )
    assert stat.gp is None
    assert stat.pts is None
    assert stat.reb is None  # never defaulted to 0


def test_multi_team_season_rows_are_distinct(db_session, sample_csv):
    ingest_csv(db_session, sample_csv)
    player = db_session.scalar(select(Player).where(Player.name_key == "eli marsh"))
    season = db_session.scalar(select(Season).where(Season.label == "2015-16"))
    rows = db_session.scalars(
        select(PlayerSeasonStats).where(
            PlayerSeasonStats.player_id == player.id,
            PlayerSeasonStats.season_id == season.id,
        )
    ).all()
    abbrs = sorted(r.team.abbreviation for r in rows)
    assert abbrs == ["CHI", "NYK", "TOT"]


def test_playoff_rows_separated(db_session, sample_csv):
    ingest_csv(db_session, sample_csv)
    player = db_session.scalar(select(Player).where(Player.name_key == "marcus vale"))
    types = {
        r.season_type
        for r in db_session.scalars(
            select(PlayerSeasonStats).where(PlayerSeasonStats.player_id == player.id)
        ).all()
    }
    assert SeasonType.PLAYOFF in types and SeasonType.REGULAR in types
