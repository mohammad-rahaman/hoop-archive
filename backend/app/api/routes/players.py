"""Player discovery endpoints: list, search, filter, pagination."""
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from app.core.config import settings
from app.db.models import SeasonType
from app.db.session import get_db
from app.schemas.common import Page
from app.schemas.player import (
    FilterOptions,
    PlayerComparison,
    PlayerDetail,
    PlayerListItem,
)
from app.services import players as players_service

router = APIRouter(prefix="/players", tags=["players"])

# Season label, e.g. "2015-16".
_SEASON = r"^\d{4}-\d{2}$"


@router.get("", response_model=Page[PlayerListItem])
def list_players(
    db: Session = Depends(get_db),
    q: Optional[str] = Query(None, description="Search by player name (accent/case-insensitive)."),
    team: Optional[str] = Query(None, description="Team abbreviation, e.g. CHI."),
    position: Optional[str] = Query(None, description="Position, e.g. PG."),
    season: Optional[str] = Query(
        None, pattern=_SEASON, description="Only players with stats in this season, e.g. 2015-16."
    ),
    page: int = Query(1, ge=1),
    page_size: Optional[int] = Query(None, ge=1),
) -> Page[PlayerListItem]:
    size = min(page_size or settings.default_page_size, settings.max_page_size)
    total, items = players_service.list_players(
        db, q=q, team=team, position=position, page=page, page_size=size, season=season
    )
    return Page.create(items=items, total=total, page=page, page_size=size)


@router.get("/filters", response_model=FilterOptions)
def player_filters(db: Session = Depends(get_db)) -> FilterOptions:
    return players_service.filter_options(db)


@router.get("/compare", response_model=PlayerComparison)
def compare_players_endpoint(
    db: Session = Depends(get_db),
    a: int = Query(..., description="First player id."),
    b: int = Query(..., description="Second player id."),
    season_type: str = Query("regular", pattern="^(regular|playoff)$"),
    a_season: Optional[str] = Query(
        None, pattern=_SEASON, description="Compare only this season for player a, e.g. 2015-16."
    ),
    b_season: Optional[str] = Query(
        None, pattern=_SEASON, description="Compare only this season for player b, e.g. 2020-21."
    ),
) -> PlayerComparison:
    if a == b and a_season == b_season:
        # The same player is fine across two different seasons (e.g. a rookie
        # year against a peak year); the identical line against itself is not.
        raise HTTPException(status_code=400, detail="Pick two different lines to compare.")
    st = SeasonType.PLAYOFF if season_type == "playoff" else SeasonType.REGULAR
    result = players_service.get_comparison(db, a, b, st, a_season, b_season)
    if result is None:
        raise HTTPException(status_code=404, detail="Player not found")
    return result


@router.get("/{player_id}", response_model=PlayerDetail)
def player_detail(player_id: int, db: Session = Depends(get_db)) -> PlayerDetail:
    detail = players_service.get_player_detail(db, player_id)
    if detail is None:
        raise HTTPException(status_code=404, detail="Player not found")
    return detail
