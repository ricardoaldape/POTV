"""NOVA real integration path with synthetic data; fail closed by default."""
import os
from urllib.parse import urlsplit, parse_qs
from unittest.mock import patch
from content_gateway import ContentGateway
from content_access import requires_vod_subscription


class NovaFake:
    def movie_source_items(self, tmdb_id, *, title=None, year=None):
        assert tmdb_id == "101"
        return [
            {"url":"https://nova.example/movie/101/master.m3u8"},
            {"url":"https://nova-fallback.example/movie/101/main.mp4"},
        ]

    def episode_source_items(self, tmdb_id, season, episode, *, title=None, year=None, is_anime=False):
        assert tmdb_id == "202"
        assert (season, episode) == (1, 3)
        return [{"url":"https://nova.example/tv/202/1/3.mp4"}]

    def _source_urls(self, rows):
        return [r["url"] for r in rows]

    def _valid_media_url(self, url):
        return url


with patch.dict(os.environ, {"POTV_NOVA_SERVICE_FILE": ""}):
    g = ContentGateway(sources=[], public_base="https://potv.example",
                       signing_secret=b"test-nova-only")
    assert g.resolve_movie(tmdb_id="101") == {"sources": []}
    assert not requires_vod_subscription(g, {})

g.nova = NovaFake()
g.nova_vod_enabled = True
assert requires_vod_subscription(g, {})
assert g.configured is False  # NOVA VOD does not expose a public TV catalog

movies = g.resolve_movie(tmdb_id="101")["sources"]
assert len(movies) == 2
assert all("nova.example" not in str(x) for x in movies)
assert all("nova-fallback" not in str(x) for x in movies)
assert all(urlsplit(x["real_url"]).hostname == "potv.example" for x in movies)
assert all("s" in parse_qs(urlsplit(x["real_url"]).query) for x in movies)
episodes = g.resolve_series_episode(tmdb_id="202",season=1,episode=3)["sources"]
assert len(episodes) == 1
assert "nova.example" not in str(episodes)
assert g._nova_candidates("movie", tmdb_id="not-an-id") == []

g.nova_vod_enabled = False
assert g.resolve_movie(tmdb_id="101") == {"sources": []}
print("PASS: NOVA opt-in VOD and episodes signed through POTV proxy; subscriptions enforced")
