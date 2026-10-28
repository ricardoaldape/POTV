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

# Both licensed connectors may have sources for the SAME title.
# NOVA may supply only an embed, while LMHD offers native MP4/HLS.
class OtherPartner:
    def movie_sources(self, *, title, year):
        assert (title, year) == ("Mi película", "2026")
        return [{"url": "https://partner.example/movie/101.mp4",
                 "format": "mp4", "language": "es-MX"}]

    def episode_sources(self, *, title, season, episode, year):
        assert (title, season, episode) == ("Mi serie", 1, 3)
        return [{"url": "https://partner.example/tv/202-1-3.m3u8",
                 "format": "hls", "language": "es-MX"}]


g.lmhd = OtherPartner()
g.lmhd_vod_enabled = True
movie_sources = g.resolve_movie(
    tmdb_id="101", title="Mi película", year="2026")["sources"]
assert len(movie_sources) == 3, movie_sources
assert all("partner.example" not in str(x) for x in movie_sources)
assert any(x.get("real_url", "").startswith("https://potv.example/")
           for x in movie_sources)
tv_sources = g.resolve_series_episode(
    tmdb_id="202", title="Mi serie", season=1, episode=3)["sources"]
assert len(tv_sources) == 2, tv_sources
assert any("format=hls" in x.get("real_url", "") for x in tv_sources)

# A denied partner cannot erase the sources from an independent provider.
from lmhd_partner import PartnerApiError
class DeniedPartner:
    def movie_sources(self, **kwargs):
        raise PartnerApiError("partner_session_denied")
    def episode_sources(self, **kwargs):
        raise PartnerApiError("partner_session_denied")

g.lmhd = DeniedPartner()
assert len(g.resolve_movie(tmdb_id="101", title="Mi película")["sources"]) == 2
assert len(g.resolve_series_episode(
    tmdb_id="202", title="Mi serie", season=1, episode=3)["sources"]) == 1

g.lmhd_vod_enabled = False
g.nova_vod_enabled = False
assert g.resolve_movie(tmdb_id="101") == {"sources": []}
print("PASS: NOVA opt-in VOD and episodes signed through POTV proxy; subscriptions enforced")
