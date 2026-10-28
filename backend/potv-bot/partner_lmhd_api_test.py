"""No network or provider secrets required: LMHD partner adapter contract tests."""
import io
import json
import os
from urllib.error import URLError
from urllib.request import HTTPRedirectHandler, Request
from urllib.parse import parse_qs, urlsplit
from unittest.mock import patch

from partner_lmhd_api import LMHDPartnerAdapter, PartnerAccessError, _NoRedirects


class FakeResponse:
    def __init__(self, value):
        self._bytes = json.dumps(value).encode()
    def __enter__(self):
        return self
    def __exit__(self, *args):
        return False
    def read(self, max_bytes):
        return self._bytes[:max_bytes]


calls = []
def fake_open(req, timeout=0):
    url = urlsplit(req.full_url)
    form = parse_qs((req.data or b"").decode())
    calls.append((url.path, parse_qs(url.query), form))
    if url.path.endswith("/login.php"):
        assert form == {"username": ["provisioned-service"], "password": ["test-password"]}
        return FakeResponse({"ok": True, "token": "fixture-token"})
    assert parse_qs(url.query)["token"] == ["fixture-token"]
    if url.path.endswith("/tv.php"):
        return FakeResponse({"ok": True, "categorias": [
            {"nombre": "Deportes", "canales": [
                {"nombre": "ESPN 2 Latin America", "media": {"url": "https://partner.example/live/test.m3u8"}, "epg": "espn2"},
                {"nombre": "Sin video", "media": {"key": "opaque"}},
                {"nombre": "Privado", "media": {"url": "http://127.0.0.1/admin"}},
            ]}]})
    if url.path.endswith("/vod.php"):
        return FakeResponse({"ok": True, "items": [{"id": 42, "title": "Película de prueba"}]})
    if url.path.endswith("/series.php"):
        return FakeResponse({"ok": True, "items": [{"id": 7, "title": "Serie de prueba"}]})
    return FakeResponse({"ok": True, "channels": []})


# A partner API 302 must never forward session tokens, even if the new URL
# is HTTPS. Verify both the handler contract and the default opener wiring.
redirect = _NoRedirects()
request = Request("https://partner.example/api/tv.php?token=fixture-token")
assert redirect.redirect_request(request, None, 302, "Found", {},
                                 "https://other.example/collect") is None
production_adapter = LMHDPartnerAdapter(
    base_url="https://partner.example/api/", username="u", password="p", device="d")
handlers = production_adapter._opener.__self__.handlers
assert sum(isinstance(h, HTTPRedirectHandler) for h in handlers) == 1
assert any(isinstance(h, _NoRedirects) for h in handlers)
with patch.dict(os.environ, {"POTV_LMHD_API_BASE_URL": "",
                             "POTV_LMHD_SERVICE_USERNAME": "",
                             "POTV_LMHD_SERVICE_PASSWORD": "",
                             "POTV_LMHD_SERVICE_DEVICE": ""}):
    assert LMHDPartnerAdapter.from_environment() is None
    with patch.dict(os.environ, {"POTV_LMHD_API_BASE_URL": "https://partner.example/api/"}):
        try:
            LMHDPartnerAdapter.from_environment()
            raise AssertionError("partial credentials accepted")
        except PartnerAccessError:
            pass

adapter = LMHDPartnerAdapter(
    base_url="https://partner.example/api/",
    username="provisioned-service",
    password="test-password",
    device="potv-qa-device",
    opener=fake_open,
)
raw = adapter.raw_channels()
assert adapter.raw_movies()["items"][0]["id"] == 42
assert adapter.raw_series()["items"][0]["id"] == 7
assert len([x for x in calls if x[0].endswith("/login.php")]) == 1
normalized = adapter.normalize_tv(raw)
assert len(normalized) == 1
assert normalized[0]["name"] == "ESPN 2 Latin America"
assert normalized[0]["epg_id"] == "espn2"
assert normalized[0]["url"].startswith("https://partner.example/")
assert all("fixture-token" not in str(row) for row in normalized)
for base in ("http://partner.example/api/", "https://127.0.0.1/api/",
             "https://user:pass@partner.example/", "https://localhost/api/"):
    try:
        LMHDPartnerAdapter(base_url=base, username="u", password="p", device="d")
        raise AssertionError("unsafe partner base accepted")
    except PartnerAccessError:
        pass
try:
    adapter.movie_detail("../admin")
    raise AssertionError("invalid movie id accepted")
except PartnerAccessError:
    pass
print("PASS: LMHD auth, no redirects, channel/category extraction, VOD and secret isolation")
