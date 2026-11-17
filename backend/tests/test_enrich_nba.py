from app.db.models import Player
from app.etl.enrich_nba import (
    clean_name,
    enrich_player_nba_ids,
    headshot_url,
    normalize_to_key,
)


def test_clean_name_and_normalize():
    assert clean_name("Michael Jordan Jr.") == "michael jordan"
    assert clean_name("Luka Dončić") == "luka doncic"
    assert clean_name("Pétur Guðmundsson") == "petur gudmundsson"
    assert clean_name("Fat Lever") == "lafayette lever"
    assert normalize_to_key("Stephen Curry II") == "stephencurry"


def test_headshot_url():
    assert headshot_url(None) is None
    assert headshot_url({}) is None
    assert headshot_url({"nba_id": 893}) == "https://cdn.nba.com/headshots/nba/latest/1040x760/893.png"
    assert (
        headshot_url({"nba_id": 2544}, size="260x190")
        == "https://cdn.nba.com/headshots/nba/latest/260x190/2544.png"
    )


def test_enrich_player_nba_ids(db_session):
    p1 = Player(full_name="Michael Jordan", name_key="michaeljordan")
    p2 = Player(full_name="Unknown Player 12345", name_key="unknownplayer12345")
    db_session.add_all([p1, p2])
    db_session.commit()

    res = enrich_player_nba_ids(db_session)
    assert res["total"] == 2
    assert res["matched"] == 1
    assert res["updated"] == 1

    assert p1.external_ids == {"nba_id": 893}
    assert p2.external_ids is None or p2.external_ids == {}
