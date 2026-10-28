"""Offline contract tests for the provider-authorized LMHD bridge.

Responses are synthetic fixture payloads, never captured user credentials.
"""
import io
import json
import tempfile
import unittest
from pathlib import Path
from urllib.parse import parse_qs, urlsplit
from urllib.error import URLError

from lmhd_partner import LmhdPartner, PartnerApiError


class Response(io.BytesIO):
    def __init__(self, request_url, data):
        super().__init__(json.dumps(data).encode("utf8"))
        self.request_url = request_url

    def geturl(self):
        return self.request_url


class Opener:
    def __init__(self):
        self.calls = []
        self.authorized = True

    def open(self, request, timeout=8):
        url = request.full_url
        uri = urlsplit(url)
        query = parse_qs(uri.query)
        self.calls.append((uri.path.rsplit("/", 1)[-1], query))
        assert uri.hostname == "api.partner.example"
        assert query.get("token") == ["test-partner-session"]
        assert query.get("device") == ["potv-test-device"]
        assert "password" not in uri.query
        if not self.authorized:
            return Response(url, {"ok": False, "error": "subscription_expired"})

        name = uri.path.rsplit("/", 1)[-1]
        if name == "tv.php":
            return Response(url, {"ok": True, "categorias": [{
                "key": "mx", "nombre": "México", "canales": [
                    {"id": 1, "nombre": "Canal Uno",
                     "media": "https://media.partner.example/mx/one.m3u8",
                     "logo": "https://images.partner.example/one.jpg",
                     "epg": [{"t": "Noticias", "s": 1000, "e": 1100}]},
                    {"id": 2, "nombre": "Falso", "media": ""}
                ]
            }]})
        if name == "channels.php":
            return Response(url, {"ok": True, "channels": [
                {"id": 22, "name": "América vs Pumas",
                 "url": "https://media.partner.example/events/22.m3u8",
                 "kickoff": 1792411200, "competencia": "Liga MX"},
                {"id": 23, "name": "Promo", "url": "", "kickoff": 1792411200},
                {"id": 24, "name": "A vs B",
                 "url": "https://media.partner.example/events/24.m3u8",
                 "kickoff": 1792411200, "finalizado": 1},
            ]})
        if name == "vod.php":
            if "q" in query and "tok" not in query:
                return Response(url, {"ok": True, "items": [
                    {"id": 76, "title": "La Casa", "year": 2022},
                    {"id": 77, "title": "La Casa", "year": 2023},
                ]})
            if "id" in query:
                return Response(url, {"ok": True, "item": {
                    "id": 77, "title": "La Casa", "year": 2023,
                    "media": {"url": "https://media.partner.example/vod/77.mp4",
                              "format": "mp4", "source": "primary"},
                    "qualities": [{"label": "720p", "media": {
                        "url": "https://media.partner.example/vod/77_720p.mp4",
                        "format": "mp4"}}]
                }})
            if "tok" in query:
                return Response(url, {"ok": True, "media": {
                    "url": "https://media.partner.example/vod/refreshed.mp4",
                    "format": "mp4"}})
        if name == "series.php":
            if "q" in query:
                return Response(url, {"ok": True, "items": [
                    {"id": 100, "title": "Mi serie", "year": 2025}]})
            if "id" in query:
                return Response(url, {"ok": True, "item": {
                    "id": 100, "title": "Mi serie", "seasons": [
                        {"n": 1, "episodes": [
                            {"id": 401, "n": 1, "locked": True},
                            {"id": 402, "n": 2, "locked": False}
                        ]}
                    ]}})
            if "tok" in query:
                return Response(url, {"ok": True, "media": {
                    "url": "https://media.partner.example/tv/402.m3u8",
                    "format": "hls", "token_ttl": 300}})
        return Response(url, {"ok": False, "error": "unknown_route"})


class LmhdContractTest(unittest.TestCase):
    def setUp(self):
        self.opener = Opener()
        self.api = LmhdPartner(
            base_url="https://api.partner.example/en-vivo/app-api/",
            token="test-partner-session",
            device="potv-test-device",
            opener=self.opener,
        )

    def test_tv_categories_and_streams_are_mapped(self):
        channels = self.api.tv_channels()
        self.assertEqual(len(channels), 1)
        self.assertEqual(channels[0]["group"], "México")
        self.assertEqual(channels[0]["name"], "Canal Uno")
        self.assertEqual(channels[0]["url"].split("/")[-1], "one.m3u8")
        self.assertEqual(channels[0]["epg_id"], "lmhd:1")
        # Invalid historic EPG from fixture does not become on-air.
        self.assertEqual(channels[0]["epg"], [])
        self.assertEqual(channels[0]["provider_id"], "1")

    def test_event_urls_match_explicit_event_ids(self):
        events = self.api.sports_events()
        self.assertEqual(len(events), 1)
        self.assertEqual(events[0]["id"], "lmhd:22")
        self.assertEqual(events[0]["home"], "América")
        self.assertEqual(events[0]["away"], "Pumas")
        self.assertEqual(events[0]["streams"][0]["url"].split("/")[-1], "22.m3u8")

    def test_vod_uses_exact_title_year_and_current_media(self):
        sources = self.api.movie_sources(title="La Casa", year="2023")
        self.assertEqual(len(sources), 2)
        self.assertEqual(sources[0]["quality"], "720p")
        self.assertTrue(any(item["url"].endswith("77.mp4") for item in sources))
        self.assertEqual(
            [q["id"] for route, q in self.opener.calls if route == "vod.php" and "id" in q],
            [["77"]]
        )

    def test_vod_refuses_ambiguous_remakes(self):
        self.assertEqual(self.api.movie_sources(title="La Casa"), [])
        self.assertEqual(self.api.movie_sources(title="Otra Película", year=2023), [])

    def test_episode_has_explicit_season_episode_and_not_locked(self):
        self.assertEqual(self.api.episode_sources(title="Mi serie", season=1, episode=1), [])
        source = self.api.episode_sources(title="Mi serie", season=1, episode=2)
        self.assertEqual(len(source), 1)
        self.assertEqual(source[0]["format"], "hls")
        self.assertTrue(source[0]["url"].endswith("402.m3u8"))

    def test_denied_token_fails_closed_without_leaking_server_error(self):
        self.opener.authorized = False
        with self.assertRaises(PartnerApiError) as error:
            self.api.tv_channels()
        self.assertEqual(error.exception.code, "partner_authorization_or_api_error")
        self.assertNotIn("subscription_expired", str(error.exception))
        self.assertNotIn(self.api.token, str(error.exception))

    def test_no_redirect_or_implicit_unknown_route(self):
        with self.assertRaises(PartnerApiError):
            self.api._request("other.php")
        with self.assertRaises(ValueError):
            LmhdPartner(base_url="http://api.partner.example/",
                        token="test", device="device")
        with self.assertRaises(ValueError):
            LmhdPartner(base_url="https://127.0.0.1/",
                        token="test", device="device")

    def test_approved_service_login_auto_renews_without_app_token(self):
        class LoginOpener:
            def __init__(self):
                self.calls = []
            def open(self, request, timeout=8):
                url = urlsplit(request.full_url)
                route = url.path.rsplit("/", 1)[-1]
                q = parse_qs(url.query)
                form = parse_qs((request.data or b"").decode("utf-8"))
                self.calls.append((route, q, form))
                if route == "login.php":
                    assert form == {
                        "username": ["potv-service"],
                        "password": ["private-fixture-password"],
                    }
                    return Response(request.full_url, {
                        "ok": True, "token": "fresh-session-from-login",
                    })
                assert q["token"] == ["fresh-session-from-login"]
                assert q["device"] == ["dedicated-device"]
                if route == "tv.php":
                    return Response(request.full_url, {"ok": True, "categorias": [
                        {"nombre": "MX", "canales": [{
                            "id": 9, "nombre": "TV Prueba",
                            "media": "https://media.partner.example/9.m3u8",
                        }]}
                    ]})
                return Response(request.full_url, {"ok": True, "channels": []})

        opening = LoginOpener()
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "licensed-service.json"
            path.write_text(json.dumps({
                "enabled": True,
                "base_url": "https://api.partner.example/",
                "username": "potv-service",
                "password": "private-fixture-password",
                "device": "dedicated-device",
            }))
            client = LmhdPartner.from_file(str(path), opener=opening)
            first = client.tv_channels()
            second = client.tv_channels()
            self.assertEqual(first[0]["provider_id"], "9")
            self.assertEqual(second[0]["name"], "TV Prueba")
            self.assertEqual([c[0] for c in opening.calls].count("login.php"), 1)
            client._session._token_at = -3601
            self.assertEqual(client.tv_channels()[0]["name"], "TV Prueba")
            self.assertEqual([c[0] for c in opening.calls].count("login.php"), 2)
            self.assertNotIn("fresh-session-from-login", repr(first))
            self.assertNotIn("private-fixture-password", repr(first))

    def test_expired_partner_session_does_not_expose_login_fields(self):
        def denied(req, timeout=9):
            raise URLError("provider_not_available: private-fixture-password")
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "approved-service.json"
            path.write_text(json.dumps({
                "enabled": True, "base_url": "https://api.partner.example/",
                "username": "potv-service", "password": "private-fixture-password",
                "device": "test-device",
            }))
            client = LmhdPartner.from_file(str(path), opener=denied)
            with self.assertRaises(PartnerApiError) as error:
                client.tv_channels()
            self.assertEqual(error.exception.code, "partner_session_denied")
            self.assertNotIn("private-fixture-password", str(error.exception))

    def test_disabled_configuration_is_not_connected(self):
        with tempfile.TemporaryDirectory() as tmp:
            f = Path(tmp)/"approved-partner.json"
            f.write_text(json.dumps({"enabled": False,
                        "base_url": "https://api.partner.example/",
                        "token": "test", "device": "test"}))
            self.assertIsNone(LmhdPartner.from_file(str(f)))


if __name__ == "__main__":
    unittest.main(verbosity=2)
