"""Application configuration, loaded from environment / .env.

The Sportradar API key is read here on the backend only and is never exposed
through any API response or to the Flutter client.
"""
from typing import Optional

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
        case_sensitive=False,
    )

    app_name: str = "Hoop Archive API"
    environment: str = "development"

    database_url: str = "postgresql+psycopg2:///hoop_archive"

    # Sportradar NBA provider (kept server-side only).
    sportradar_api_key: Optional[str] = None
    sportradar_base_url: str = "https://api.sportradar.com/nba/trial/v8/en"
    # Sportradar access level used only to label provenance (trial vs production).
    sportradar_access_level: str = "trial"
    sportradar_timeout_seconds: float = 15.0

    # Scheduled sync. Disabled by default; a sync only runs when a key is present
    # AND this is turned on, so no external calls happen out of the box.
    sync_enabled: bool = False
    sync_interval_hours: float = 24.0
    # Season (start year) the scheduled sync refreshes, e.g. 2024 for 2024-25.
    # When unset, no scheduled sync is attempted even if enabled.
    sync_season_year: Optional[int] = None
    # Comma-separated Sportradar team ids to refresh (required for a live sync;
    # never guessed). Example: "sr:team:3410,sr:team:3415".
    sync_team_ids: Optional[str] = None
    # Optional shared secret protecting the manual sync trigger endpoint.
    sync_admin_token: Optional[str] = None

    # Pagination guards.
    default_page_size: int = 25
    max_page_size: int = 100

    @property
    def sportradar_configured(self) -> bool:
        return bool(self.sportradar_api_key)

    @property
    def sync_team_id_list(self) -> list[str]:
        if not self.sync_team_ids:
            return []
        return [t.strip() for t in self.sync_team_ids.split(",") if t.strip()]

    @property
    def scheduled_sync_active(self) -> bool:
        """Whether a background sync should actually run on a timer."""
        return (
            self.sync_enabled
            and self.sportradar_configured
            and self.sync_season_year is not None
            and bool(self.sync_team_id_list)
        )


settings = Settings()
