import httpx
import pytest

from app.providers.sportradar import (
    SportradarClient,
    SportradarError,
    SportradarNotConfigured,
)


def test_unconfigured_client_raises():
    client = SportradarClient(api_key=None)
    assert client.configured is False
    with pytest.raises(SportradarNotConfigured):
        client.seasonal_team_statistics(2024, "REG", "sr:team:1")


def test_client_sends_key_and_parses_json():
    captured = {}

    def handler(request: httpx.Request) -> httpx.Response:
        captured["url"] = str(request.url)
        captured["api_key"] = request.url.params.get("api_key")
        return httpx.Response(200, json={"season": {"year": 2024, "type": "REG"}})

    transport = httpx.MockTransport(handler)
    http = httpx.Client(transport=transport)
    client = SportradarClient(api_key="secret-key", base_url="https://x/nba", http=http)

    data = client.seasonal_team_statistics(2024, "REG", "sr:team:3410")
    assert data["season"]["year"] == 2024
    # The key is sent to Sportradar, and only there.
    assert captured["api_key"] == "secret-key"
    assert "seasons/2024/REG/teams/sr:team:3410/statistics.json" in captured["url"]


def test_client_raises_on_auth_error():
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(403, json={"error": "forbidden"})

    client = SportradarClient(
        api_key="bad",
        base_url="https://x/nba",
        http=httpx.Client(transport=httpx.MockTransport(handler)),
    )
    with pytest.raises(SportradarError):
        client.seasonal_team_statistics(2024, "REG", "sr:team:1")
