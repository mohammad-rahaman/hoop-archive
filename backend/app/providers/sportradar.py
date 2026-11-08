"""Sportradar NBA API client.

Security & licensing notes
--------------------------
* The API key is read from backend settings only and is sent to Sportradar as a
  query parameter. It is **never** returned in any API response or exposed to the
  Flutter client — all provider calls are proxied here.
* Sportradar trial data is for internal evaluation only. This client fetches data
  for storage/display inside the app; it must not be used to publicly redistribute
  trial data without proper rights.
* When no API key is configured the client raises ``SportradarNotConfigured`` so
  callers can fall back to existing sample/historical data. Credentials are never
  invented or defaulted.
"""
from __future__ import annotations

from typing import Any, Dict, Optional

import httpx

from app.core.config import settings


class SportradarError(RuntimeError):
    """Base class for Sportradar client failures."""


class SportradarNotConfigured(SportradarError):
    """Raised when no API key is available — the caller should use local data."""


class SportradarClient:
    """Thin, injectable wrapper over the Sportradar NBA v8 endpoints we use.

    ``http`` can be supplied (e.g. an ``httpx.Client`` backed by a mock transport)
    for testing without real network access.
    """

    def __init__(
        self,
        api_key: Optional[str] = None,
        base_url: Optional[str] = None,
        timeout: Optional[float] = None,
        http: Optional[httpx.Client] = None,
    ) -> None:
        self._api_key = api_key if api_key is not None else settings.sportradar_api_key
        self._base_url = (base_url or settings.sportradar_base_url).rstrip("/")
        self._timeout = timeout or settings.sportradar_timeout_seconds
        self._http = http
        self._owns_http = http is None

    @property
    def configured(self) -> bool:
        return bool(self._api_key)

    def _client(self) -> httpx.Client:
        if self._http is None:
            self._http = httpx.Client(timeout=self._timeout)
        return self._http

    def close(self) -> None:
        if self._owns_http and self._http is not None:
            self._http.close()
            self._http = None

    def __enter__(self) -> "SportradarClient":
        return self

    def __exit__(self, *exc: object) -> None:
        self.close()

    def _get(self, path: str, params: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        if not self.configured:
            raise SportradarNotConfigured(
                "Sportradar API key is not configured. Set SPORTRADAR_API_KEY to "
                "enable live sync; the app continues to serve existing data."
            )
        url = f"{self._base_url}/{path.lstrip('/')}"
        query = dict(params or {})
        query["api_key"] = self._api_key
        try:
            resp = self._client().get(url, params=query)
        except httpx.HTTPError as exc:  # network/timeout
            raise SportradarError(f"Sportradar request failed: {exc}") from exc
        if resp.status_code == 401 or resp.status_code == 403:
            raise SportradarError(
                f"Sportradar rejected the API key (HTTP {resp.status_code})."
            )
        if resp.status_code >= 400:
            raise SportradarError(
                f"Sportradar returned HTTP {resp.status_code} for {path}."
            )
        try:
            return resp.json()
        except ValueError as exc:
            raise SportradarError("Sportradar returned a non-JSON response.") from exc

    def seasonal_team_statistics(
        self, season_year: int, season_type: str, team_id: str
    ) -> Dict[str, Any]:
        """Season averages/totals for a single team's players.

        ``season_type`` is Sportradar's code: ``REG`` (regular) or ``PST``
        (postseason/playoffs).
        """
        path = f"seasons/{season_year}/{season_type}/teams/{team_id}/statistics.json"
        return self._get(path)
