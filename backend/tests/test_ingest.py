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


def test_ingest_bref_style_csv_handles_dups_end_years_team_names_and_replace(
    db_session, sample_csv, tmp_path
):
    # First seed with synthetic data, then replace using a Basketball-Reference style CSV.
    ingest_csv(db_session, sample_csv)
    assert db_session.scalar(select(Player).where(Player.name_key == "marcus vale")) is not None

    bref_csv = tmp_path / "bref.csv"
    bref_csv.write_text(
        "Player,Pos,Tm,Team,G,PTS,Year\n"
        "Michael Jordan,SF,WAS,Washington Wizards,60,22.9,2002.0\n"
        "Michael Jordan,SG,CHI,Chicago Bulls,82,31.5,1991.0\n"
        "Michael Jordan,SG,CHI,Chicago Bulls,80,30.1,1992.0\n"
        "Dee Brown,PG,BOS,Boston Celtics,80,10.9,1993.0\n"
        "Dee Brown,PG,BOS,Boston Celtics,80,10.9,1993.0\n",
        encoding="utf-8",
    )

    res = ingest_csv(
        db_session, str(bref_csv), bare_year_is_end=True, replace_existing=True
    )
    assert res.rows_read == 5
    assert res.rows_skipped == 0
    assert res.stats_inserted == 4
    assert res.stats_updated == 1

    # Synthetic data was cleared.
    assert db_session.scalar(select(Player).where(Player.name_key == "marcus vale")) is None

    # Primary position picked by GP weight (SG over SF despite SF appearing first).
    mj = db_session.scalar(select(Player).where(Player.name_key == "michael jordan"))
    assert mj is not None and mj.position == "SG"

    # Season end year 1991.0 became 1990-91, and Team.name was populated.
    chi = db_session.scalar(select(Team).where(Team.abbreviation == "CHI"))
    assert chi is not None and chi.name == "Chicago Bulls"
    seasons = {
        s.label for s in db_session.scalars(select(Season)).all()
    }
    assert seasons == {"1990-91", "1991-92", "1992-93", "2001-02"}
