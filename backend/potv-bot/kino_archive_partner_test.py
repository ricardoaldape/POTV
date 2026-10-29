"""Offline tests for Kino's opt-in Internet Archive native movie bridge."""
import io
import json
import os
from unittest.mock import patch
from urllib.parse import urlsplit, parse_qs
from content_gateway import ContentGateway
from content_access import requires_vod_subscription
from kino_archive_partner import KinoArchivePartner, permitted_license


class FakeResponse(io.BytesIO):
    def __enter__(self):
        return self
    def __exit__(self, *a):
        self.close()


calls = []
def mock_transport(request, timeout):
    url = request.full_url
    calls.append(url)
    if "advancedsearch.php" in url:
        result = {"response": {"docs": [
            {"identifier": "another_movie", "title": "Unrelated title",
             "licenseurl": "https://creativecommons.org/publicdomain/mark/1.0/"},
            {"identifier": "licensed_archive_film", "title": "Night Of The Living Dead",
             "year": "1968", "licenseurl": "https://creativecommons.org/publicdomain/mark/1.0/"},
            {"identifier": "unlicensed", "title": "Night Of The Living Dead",
             "licenseurl": "https://other.example/license"},
        ]}}
    else:
        assert url.endswith("/metadata/licensed_archive_film")
        result = {
            "metadata": {"licenseurl": "https://creativecommons.org/publicdomain/mark/1.0/"},
            "files": [
                {"name": "cover.jpg", "size": "12345"},
                {"name": "../private.mp4", "size": "222000"},
                {"name": "Living Dead.mp4", "size": "500000000", "source": "original"},
            ],
        }
    return FakeResponse(json.dumps(result).encode("utf-8"))


partner = KinoArchivePartner(transport=mock_transport)
sources = partner.movie_sources(title="Night of the Living Dead", year="1968")
assert len(sources) == 1, sources
assert sources[0]["url"].startswith(
    "https://archive.org/download/licensed_archive_film/")
assert "Living%20Dead.mp4" in sources[0]["url"]
assert len(calls) == 2
assert partner.movie_sources(title="Night of the Living Dead", year="1968") == sources
assert len(calls) == 2, "expected TTL cache"
assert partner.movie_sources(title="Secret", year="1968") == []
assert partner.movie_sources(title="Night of the Living Dead", year="nope") == sources
assert not permitted_license("https://third.party/license")
assert permitted_license("https://creativecommons.org/publicdomain/zero/1.0/")

with patch.dict(os.environ, {
    "POTV_KINO_ARCHIVE_ENABLED": "true",
    "POTV_NOVA_SERVICE_FILE": "",
    "POTV_LMHD_VOD_ENABLED": "false",
}):
    gateway = ContentGateway(
        sources=[],
        public_base="https://potv.example",
        signing_secret=b"kino-archive-test-secret")
gateway.kino_archive = partner
assert requires_vod_subscription(gateway, {})
payload = gateway.resolve_movie(
    tmdb_id=None, title="Night of the Living Dead", year="1968")
assert len(payload["sources"]) == 1, payload
uri = payload["sources"][0]["real_url"]
assert urlsplit(uri).hostname == "potv.example"
assert parse_qs(urlsplit(uri).query)["format"] == ["mp4"]
assert urlsplit(uri).path.startswith("/api/v1/content/stream/")
assert "archive.org" not in json.dumps(payload)
assert "licensed_archive_film" not in json.dumps(payload)
assert gateway.resolve_movie(title="No licensed film") == {"sources": []}

with patch.dict(os.environ, {
    "POTV_KINO_ARCHIVE_ENABLED": "false",
    "POTV_NOVA_SERVICE_FILE": "",
}):
    disabled = ContentGateway(sources=[], signing_secret=b"kino-archive-test")
assert disabled.kino_archive is None
assert not requires_vod_subscription(disabled, {})
print("PASS: Kino Archive title, domain, license, source pin, expiry, cache and subscription")
