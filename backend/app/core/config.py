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

    # Connection pool, sized PER WORKER PROCESS. Under a multi-worker server the
    # total connections opened against Postgres is
    #   workers * (db_pool_size + db_max_overflow)
    # which must stay below the server's max_connections (default 100). See
    # gunicorn_conf.py, which derives the worker count from this budget.
    db_pool_size: int = 10
    db_max_overflow: int = 5
    # Seconds a request waits for a free connection before failing fast. This is
    # the key load-shedding guard: under overload requests get a quick error
    # instead of piling up and wedging the process.
    db_pool_timeout: float = 10.0
    db_pool_recycle: int = 1800
    # Postgres statement timeout (ms) applied per connection, so a runaway query
    # is cancelled and its connection returned instead of being held forever.
    db_statement_timeout_ms: int = 15000

    # Whether this process runs the in-process background sync scheduler. Under a
    # multi-worker server exactly one worker should set this (gunicorn_conf.py
    # does so), otherwise every worker would run its own sync loop.
    enable_scheduler: bool = True

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
