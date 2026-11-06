"""Provider abstraction for current/recent data sources.

Sportradar is one implementation (added in Phase 7). The abstraction lets another
licensed provider be swapped in without touching the API or ingestion layers.
All provider calls happen on the backend; API keys never reach the client.
"""
from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import List, Optional


@dataclass
class ProviderPlayer:
    external_id: str
    full_name: str
    position: Optional[str] = None
    jersey_number: Optional[str] = None
    team_abbr: Optional[str] = None


@dataclass
class ProviderSeasonStat:
    external_player_id: str
    season_label: str
    team_abbr: Optional[str]
    season_type: str  # 'regular' | 'playoff'
    # Only set the metrics the provider actually returns; leave others None.
    stats: dict = None


class StatsProvider(ABC):
    """Interface every current-data provider must implement."""

    name: str = "abstract"

    @abstractmethod
    def is_configured(self) -> bool:
        """True when credentials/config are present."""

    @abstractmethod
    def list_players(self, season_label: str) -> List[ProviderPlayer]:
        ...

    @abstractmethod
    def season_stats(self, season_label: str, season_type: str = "regular") -> List[ProviderSeasonStat]:
        ...
