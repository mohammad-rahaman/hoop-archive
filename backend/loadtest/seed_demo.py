"""Seed a small SYNTHETIC dataset for load testing / CI only.

This generates fake players and stats so the API has something to serve. It is
NOT real NBA data and is unrelated to the Kaggle/Sportradar sources, so it can
run anywhere without any data-licensing concerns. Never use it to populate a
real deployment.

    cd backend
    DATABASE_URL=postgresql+psycopg2:///hoop_archive_ci python3 loadtest/seed_demo.py 200
"""
import random
import sys

from app.db.base import Base
from app.db.models import (
    Player,
    PlayerSeasonStats,
    Season,
    SeasonType,
    StatMode,
    SyncMetadata,
    Team,
)
from app.db.session import SessionLocal, engine
from app.etl.columns import normalize_name_key

TEAMS = ["ATL", "BOS", "CHI", "DAL", "DEN", "GSW", "LAL", "MIA", "NYK", "PHX"]
POSITIONS = ["PG", "SG", "SF", "PF", "C"]


def seed(n_players: int = 200) -> None:
    Base.metadata.create_all(engine)
    rng = random.Random(42)

    with SessionLocal() as db:
        if db.query(Player).first() is not None:
            print("DB already has players; leaving it untouched.")
            return

        teams = [Team(abbreviation=a, name=f"{a} Club") for a in TEAMS]
        db.add_all(teams)
        seasons = [
            Season(label=f"{y}-{str(y + 1)[2:]}", year_start=y)
            for y in range(2000, 2020)
        ]
        db.add_all(seasons)
        db.flush()

        for i in range(n_players):
            name = f"Demo Player {i:04d}"
            player = Player(
                name_key=normalize_name_key(name),
                full_name=name,
                position=rng.choice(POSITIONS),
                jersey_number=str(rng.randint(0, 55)),
                external_ids={},
            )
            db.add(player)
            db.flush()
            n_seasons = rng.randint(1, 8)
            for season in rng.sample(seasons, n_seasons):
                team = rng.choice(teams)
                db.add(
                    PlayerSeasonStats(
                        player_id=player.id,
                        season_id=season.id,
                        team_id=team.id,
                        season_type=SeasonType.REGULAR,
                        stat_mode=StatMode.PER_GAME,
                        gp=rng.randint(10, 82),
                        min=round(rng.uniform(8, 38), 1),
                        pts=round(rng.uniform(2, 30), 1),
                        reb=round(rng.uniform(1, 14), 1),
                        ast=round(rng.uniform(0, 11), 1),
                        stl=round(rng.uniform(0, 2.5), 1),
                        blk=round(rng.uniform(0, 3), 1),
                        tov=round(rng.uniform(0, 4), 1),
                        fg_pct=round(rng.uniform(0.38, 0.62), 3),
                        fg3_pct=round(rng.uniform(0.28, 0.44), 3),
                        ft_pct=round(rng.uniform(0.6, 0.92), 3),
                        source="synthetic_demo",
                    )
                )
        db.add(
            SyncMetadata(
                provider="synthetic_demo",
                source_label="load-test seed (not real data)",
                rows_ingested=n_players,
                status="success",
            )
        )
        db.commit()
        print(f"Seeded {n_players} synthetic players across {len(seasons)} seasons.")


if __name__ == "__main__":
    count = int(sys.argv[1]) if len(sys.argv) > 1 else 200
    seed(count)
