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


@router.get("", response_model=Page[PlayerListItem])
def list_players(
    db: Session = Depends(get_db),
    q: Optional[str] = Query(None, description="Search by player name (accent/case-insensitive)."),
    team: Optional[str] = Query(None, description="Team abbreviation, e.g. CHI."),
    position: Optional[str] = Query(None, description="Position, e.g. PG."),
    page: int = Query(1, ge=1),
    page_size: Optional[int] = Query(None, ge=1),
) -> Page[PlayerListItem]:
    size = min(page_size or settings.default_page_size, settings.max_page_size)
    total, items = players_service.list_players(
        db, q=q, team=team, position=position, page=page, page_size=size
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
) -> PlayerComparison:
    if a == b:
        raise HTTPException(status_code=400, detail="Pick two different players.")
    st = SeasonType.PLAYOFF if season_type == "playoff" else SeasonType.REGULAR
    result = players_service.get_comparison(db, a, b, st)
    if result is None:
        raise HTTPException(status_code=404, detail="Player not found")
    return result


@router.get("/{player_id}", response_model=PlayerDetail)
def player_detail(player_id: int, db: Session = Depends(get_db)) -> PlayerDetail:
    detail = players_service.get_player_detail(db, player_id)
    if detail is None:
        raise HTTPException(status_code=404, detail="Player not found")
    return detail
