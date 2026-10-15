"""Integration smoke: optional approved LMHD adapter attaches to POTV gateway."""
from urllib.parse import urlsplit, parse_qs
from content_gateway import ContentGateway


class AuthorizedFixture:
    def tv_channels(self):
        return [{
            "name": "Canal Uno",
            "url": "https://media.partner.example/live/uno.m3u8",
            "logo": "https://images.partner.example/logo.jpg",
            "group": "México", "headers": {},
        }]

    def sports_events(self):
        return [{
            "id": "lmhd:match-12",
            "sport": "Fútbol",
            "competition": "Liga MX",
            "home": "América",
            "away": "Pumas",
            "starts_at": "2026-10-18T20:00:00+00:00",
            "is_live": False,
            "streams": [{"url": "https://media.partner.example/event/match-12.m3u8"}],
        }]

    def movie_sources(self, *, title, year):
        assert title == "La Casa" and year == "2023"
        return [{"url": "https://media.partner.example/vod/77.mp4",
                 "quality": "1080p", "format": "mp4", "language": "es-MX"}]

    def episode_sources(self, *, title, season, episode, year):
        assert title == "Mi serie" and season == 1 and episode == 2
        return [{"url": "https://media.partner.example/tv/402.m3u8",
                 "quality": "720p", "format": "hls", "language": "es-MX"}]


gateway = ContentGateway(
    sources=[], public_base="https://potv.example",
    signing_secret=b"fixture-bridge-secret"
)
gateway.lmhd = AuthorizedFixture()
gateway.lmhd_live_catalog_enabled = True
payload = gateway.catalog(force=True)["data"]
assert len(payload["channels"]) == 1, payload
assert len(payload["sports_channels"]) == 0, payload
assert len(payload["sports_events"]) == 1, payload
assert payload["sports_events"][0]["home"] == "América"
assert payload["sports_events"][0]["away"] == "Pumas"
assert "media.partner.example" not in str(payload)
for row in payload["channels"]:
    assert row["hls_url"].startswith("https://potv.example/api/v1/content/stream/")
    assert "format=hls" in row["hls_url"]
for event in payload["sports_events"]:
    assert event["streams"][0]["url"].startswith("https://potv.example/api/v1/content/stream/")

movie = gateway.resolve_movie(title="La Casa", year="2023")["sources"]
assert len(movie) == 1
assert movie[0]["quality"] == "1080p"
assert "media.partner.example" not in str(movie)
assert urlsplit(movie[0]["real_url"]).hostname == "potv.example"

episode = gateway.resolve_series_episode(
    title="Mi serie", year="2025", season=1, episode=2
)["sources"]
assert len(episode) == 1
assert "format=hls" in episode[0]["real_url"]
url = urlsplit(episode[0]["real_url"])
assert "s" in parse_qs(url.query)  # short-lived POTV signature
assert "token" not in url.query
print("PASS: LMHD provider movie, episode, TV and exact-match sports integrated via POTV gateway")
