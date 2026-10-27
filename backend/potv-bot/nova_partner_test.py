"""Offline contract tests inferred from NOVA 1.2.9's ApiService."""
import io
import json
from urllib.parse import urlsplit, parse_qs
from nova_partner import NovaPartner, NovaPartnerError


class FakeResponse(io.BytesIO):
    status = 200
    def __enter__(self):
        return self
    def __exit__(self, *_):
        self.close()


class FakeOpener:
    def __init__(self):
        self.calls = []

    def open(self, request, timeout=0):
        uri = urlsplit(request.full_url)
        assert uri.hostname == "partner.example"
        assert request.get_header("Authorization") == "Bearer dedicated-test"
        self.calls.append((uri.path, parse_qs(uri.query)))
        path = uri.path
        if path.endswith("/movies/"):
            body = {"data": {"items": [{"id": 1, "title": "Demo Movie"}]}}
        elif path.endswith("/series/"):
            body = {"data": {"results": [{"id": 2, "title": "Demo Series"}]}}
        elif path.endswith("/anime/"):
            body = [{"id": 3, "title": "Demo Anime"}]
        elif path.endswith("/channels/all_lite"):
            body = {"data": {"channels": [{"id": "sports-1", "name": "Test Sports"}]}}
        elif path.endswith("/channels/stream/sports-1"):
            body = {"data": {
                "primary_url": "https://cdn.example/test.m3u8",
                "backup_urls": [
                    {"url": "https://cdn2.example/test.m3u8"},
                    "http://insecure.example/test.m3u8",
                    "https://cdn.example/test.m3u8",
                ],
            }}
        elif path.endswith("/vod/sources/movie/101"):
            body = {"data": {"sources": [
                {"url": "https://cdn.example/movie.m3u8"},
                {"url": "javascript:alert(1)"},
            ]}}
        elif path.endswith("/vod/sources/tv/202/1/5"):
            body = {"data": {"primary_url": "https://cdn.example/episode.mp4"}}
        elif path.endswith("/app/version"):
            body = {"data": {"version": "1.2.9"}}
        else:
            raise AssertionError("Unexpected API request: " + path)
        return FakeResponse(json.dumps(body).encode())


opener = FakeOpener()
api = NovaPartner(
    base_url="https://partner.example/api/v1/",
    access_token="dedicated-test", opener=opener,
)
assert len(api.movies(skip=0,limit=80)) == 1
assert len(api.series()) == 1
assert len(api.anime()) == 1
assert api.channels()[0]["id"] == "sports-1"
assert api.channel_streams("sports-1") == [
    "https://cdn.example/test.m3u8",
    "https://cdn2.example/test.m3u8",
]
assert api.movie_sources(101) == ["https://cdn.example/movie.m3u8"]
assert api.episode_sources(202,1,5) == ["https://cdn.example/episode.mp4"]
assert api.app_version() == {"version": "1.2.9"}

for bad in ("http://partner.example/api/", "https://partner.example/api/?key=abc",
            "https://user:pass@partner.example/api/", "https://127.0.0.1/"):
    try:
        api2 = NovaPartner(base_url=bad,access_token="test")
        assert bad != "https://127.0.0.1/", "private host should be disallowed"
    except ValueError:
        pass

try:
    api.channel_streams("../secret")
    raise AssertionError("Path traversal accepted")
except ValueError:
    pass
try:
    api.movie_sources("invalid")
    raise AssertionError("Invalid movie id accepted")
except ValueError:
    pass
assert opener.calls[0][0] == "/api/v1/movies/"
assert opener.calls[-1][0] == "/api/v1/app/version"
print("PASS: NOVA API catalog, movie/episode playback, live backups, and input validation")
