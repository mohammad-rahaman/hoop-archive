"""Player-related response schemas."""
from typing import List, Optional

from pydantic import BaseModel


class PlayerListItem(BaseModel):
    id: int
    full_name: str
    position: Optional[str] = None
    latest_team: Optional[str] = None
    teams: List[str] = []
    season_count: int = 0
    first_year: Optional[int] = None
    last_year: Optional[int] = None
    latest_season: Optional[str] = None
    image_url: Optional[str] = None

    @property
    def career_span(self) -> Optional[str]:  # pragma: no cover - display helper
        if self.first_year is None or self.last_year is None:
            return None
        return f"{self.first_year}-{str(self.last_year + 1)[-2:]}"


class SeasonStatRow(BaseModel):
    season: str
    year_start: int
    season_type: str  # 'regular' | 'playoff'
    team: str
    stat_mode: str
    source: str

    gp: Optional[int] = None
    min: Optional[float] = None
    pts: Optional[float] = None
    reb: Optional[float] = None
    ast: Optional[float] = None
    stl: Optional[float] = None
    blk: Optional[float] = None
    tov: Optional[float] = None
    fgm: Optional[float] = None
    fga: Optional[float] = None
    fg_pct: Optional[float] = None
    fg3m: Optional[float] = None
    fg3a: Optional[float] = None
    fg3_pct: Optional[float] = None
    ftm: Optional[float] = None
    fta: Optional[float] = None
    ft_pct: Optional[float] = None
    per: Optional[float] = None
    ts_pct: Optional[float] = None
    usg_pct: Optional[float] = None


class PlayerDetail(BaseModel):
    id: int
    full_name: str
    position: Optional[str] = None
    jersey_number: Optional[str] = None
    teams: List[str] = []
    first_year: Optional[int] = None
    last_year: Optional[int] = None
    season_count: int = 0
    has_playoffs: bool = False
    image_url: Optional[str] = None
    seasons: List[SeasonStatRow] = []


class FilterOptions(BaseModel):
    teams: List[str]
    positions: List[str]
    # Season labels with recorded stats, newest first, e.g. "2020-21".
    seasons: List[str] = []


class ComparisonPlayer(BaseModel):
    id: int
    full_name: str
    position: Optional[str] = None
    teams: List[str] = []
    first_year: Optional[int] = None
    last_year: Optional[int] = None
    season_count: int = 0
    image_url: Optional[str] = None
    # Set when this side compares one season instead of the career.
    season: Optional[str] = None
    # Team for that season ("TOT" when split across teams), or None.
    season_team: Optional[str] = None


class MetricComparisonRow(BaseModel):
    key: str
    label: str
    unit: str
    percent: bool
    a_value: Optional[float] = None
    b_value: Optional[float] = None
    leader: Optional[str] = None  # 'a' | 'b' | 'tie' | None (unavailable)
    available: bool = False


class PlayerComparison(BaseModel):
    season_type: str  # 'regular' | 'playoff'
    a: ComparisonPlayer
    b: ComparisonPlayer
    metrics: List[MetricComparisonRow] = []
    a_wins: int = 0
    b_wins: int = 0
    ties: int = 0
