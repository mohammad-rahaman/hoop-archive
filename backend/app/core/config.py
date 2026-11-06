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

    # Pagination guards.
    default_page_size: int = 25
    max_page_size: int = 100

    @property
    def sportradar_configured(self) -> bool:
        return bool(self.sportradar_api_key)


settings = Settings()
