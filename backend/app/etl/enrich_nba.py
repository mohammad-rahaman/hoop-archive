"""Enrich player records with official NBA person IDs and headshot URLs.

Loads the NBA official players registry (cached in
``backend/data/nba_players_registry.json``) and matches players using
accent-insensitive, suffix-stripped name keys and nickname aliases.
"""
import json
import logging
import re
import unicodedata
from pathlib import Path
from typing import Dict, List, Optional, Tuple

from sqlalchemy.orm import Session

from app.db.models import Player
from app.db.session import SessionLocal

logger = logging.getLogger(__name__)

DEFAULT_REGISTRY_PATH = Path(__file__).resolve().parents[2] / "data" / "nba_players_registry.json"

# Common historical nicknames / aliases mapping to NBA official registry names.
NICKNAMES: Dict[str, str] = {
    "fat lever": "lafayette lever",
    "tiny archibald": "nate archibald",
    "clarence weatherspoon": "clar weatherspoon",
    "danny schayes": "dan schayes",
    "cheese johnson": "eddie johnson",
    "bubba wilson": "rick wilson",
    "dave greenwood": "david greenwood",
    "ronald murray": "flip murray",
    "mike sweetney": "michael sweetney",
    "clar weatherspoon": "clar weatherspoon",
    "petur gudmundsson": "petur gudmundsson",
    "isaac austin": "ike austin",
    "charles pittman": "charlie pittman",
    "melvin turpin": "mel turpin",
    "omer asik": "omer asik",
    "world b free": "world free",
    "gar heard": "garfield heard",
    "ron grandison": "ronnie grandison",
    "ibo kutluay": "ibrahim kutluay",
    "rich manning": "richard manning",
    "cliff robinson": "cliff t robinson",
    "clifford robinson": "cliff t robinson",
    "steve smith": "steven smith",
    "jimmy butler": "jimmy butler",
    "bobby portis": "bobby portis",
}


def clean_name(text: str) -> str:
    """Normalize a name: transliterate special chars, strip suffixes and punctuation."""
    if not text:
        return ""
    text = text.replace("ð", "d").replace("Ð", "D")
    text = text.replace("ı", "i").replace("İ", "I")
    text = unicodedata.normalize("NFKD", text)
    text = "".join(c for c in text if not unicodedata.combining(c))
    text = text.lower()
    text = re.sub(r"\b(jr|sr|ii|iii|iv)\b", "", text)
    text = re.sub(r"[^a-z0-9\s]", "", text)
    text = " ".join(text.split())
    return NICKNAMES.get(text, text)


def normalize_to_key(text: str) -> str:
    """Strip all non-alphanumeric chars after clean_name."""
    return re.sub(r"[^a-z0-9]", "", clean_name(text))


def headshot_url(external_ids: Optional[dict], size: str = "1040x760") -> Optional[str]:
    """Derive official NBA CDN headshot URL from player's external_ids.

    Supported sizes: '1040x760' (high-res) or '260x190' (compact).
    """
    if not external_ids or not isinstance(external_ids, dict):
        return None
    nba_id = external_ids.get("nba_id")
    if not nba_id:
        return None
    return f"https://cdn.nba.com/headshots/nba/latest/{size}/{nba_id}.png"


def load_nba_registry(path: Optional[Path] = None) -> List[Tuple[int, str]]:
    """Load NBA players registry list [id, last, first, full, is_active]."""
    target = path or DEFAULT_REGISTRY_PATH
    if not target.exists():
        raise FileNotFoundError(f"NBA players registry not found at {target}")
    with open(target, "r", encoding="utf-8") as f:
        data = json.load(f)
    # Return list of (nba_id, full_name, first_name, last_name)
    registry = []
    for item in data:
        pid, last, first, full = item[0], item[1], item[2], item[3]
        registry.append((pid, full, first, last))
    return registry


def build_nba_lookup_map(registry: List[Tuple[int, str, str, str]]) -> Dict[str, int]:
    lookup: Dict[str, int] = {}
    for pid, full, first, last in registry:
        lookup[normalize_to_key(full)] = pid
        lookup[normalize_to_key(f"{first} {last}")] = pid
    return lookup


def enrich_player_nba_ids(
    db: Session, registry_path: Optional[Path] = None
) -> Dict[str, int]:
    """Match database players against official NBA registry and save nba_id into external_ids."""
    registry = load_nba_registry(registry_path)
    lookup = build_nba_lookup_map(registry)

    players = db.query(Player).all()
    total = len(players)
    matched = 0
    updated = 0

    for p in players:
        k = normalize_to_key(p.full_name)
        nba_id = lookup.get(k)
        if nba_id:
            matched += 1
            cur_ids = dict(p.external_ids or {})
            if cur_ids.get("nba_id") != nba_id:
                cur_ids["nba_id"] = nba_id
                p.external_ids = cur_ids
                updated += 1

    if updated > 0:
        db.commit()

    return {"total": total, "matched": matched, "updated": updated}


def main():
    db = SessionLocal()
    try:
        res = enrich_player_nba_ids(db)
        print(
            f"Enrichment complete: total={res['total']}, "
            f"matched={res['matched']} ({res['matched']/res['total']*100:.1f}%), "
            f"updated={res['updated']}"
        )
    finally:
        db.close()


if __name__ == "__main__":
    main()
