"""Offline contract tests for the provider-authorized LMHD bridge.

Responses are synthetic fixture payloads, never captured user credentials.
"""
import io
import json
import tempfile
import unittest
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

from lmhd_partner import LmhdPartner, LmhdLoginPartner, PartnerApiError
from partner_lmhd_api import PartnerAccessError
from unittest.mock import patch
import os


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
                    {"id": 2, "nombre": "Canal Dos",
                     "media": {"url": "https://media.partner.example/mx/two.m3u8",
                               "format": "hls", "language": "es-MX"}},
                    {"id": 3, "nombre": "Falso", "media": ""}
                ]
            }]})
        if name == "channels.php":
            return Response(url, {"ok": True, "channels": [
                {"id": 22, "name": "América vs Pumas",
                 "url": "https://media.partner.example/events/22.m3u8",
                 "kickoff": 1792411200, "competencia": "Liga MX"},
                {"id": 23, "name": "B vs C",
                 "media": {"url": "https://media.partner.example/events/23.m3u8",
                           "format": "hls"},
                 "kickoff": 1792411200},
                {"id": 25, "name": "Promo", "url": "", "kickoff": 1792411200},
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
        self.assertEqual(len(channels), 2)
        self.assertEqual(channels[1]["name"], "Canal Dos")
        self.assertEqual(channels[1]["url"], "https://media.partner.example/mx/two.m3u8")
        self.assertEqual(channels[0]["group"], "México")
        self.assertEqual(channels[0]["name"], "Canal Uno")
        self.assertEqual(channels[0]["url"].split("/")[-1], "one.m3u8")
        self.assertEqual(channels[0]["epg_id"], "lmhd:1")
        # Invalid historic EPG from fixture does not become on-air.
        self.assertEqual(channels[0]["epg"], [])
        self.assertEqual(channels[0]["provider_id"], "1")

    def test_event_urls_match_explicit_event_ids(self):
        events = self.api.sports_events()
        self.assertEqual(len(events), 2)
        self.assertEqual(events[1]["streams"][0]["url"],
                         "https://media.partner.example/events/23.m3u8")
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

    def test_login_service_account_uses_same_tv_and_event_parser(self):
        class LoggedIn:
            def __init__(self):
                self.paths = []
            def _authenticated(self, route, fields):
                self.paths.append(route)
                if route == "tv.php":
                    return {"ok": True, "categorias": [{
                        "nombre": "México", "canales": [{
                            "id": 31, "nombre": "Canal con media objeto",
                            "media": {"url": "https://media.partner.example/31.m3u8",
                                      "format": "hls"},
                        }]}]}
                if route == "channels.php":
                    return {"ok": True, "channels": []}
                return {"ok": True, "items": []}
        adapter = LoggedIn()
        partner = LmhdLoginPartner(adapter)
        rows = partner.tv_channels()
        self.assertEqual(rows[0]["provider_id"], "31")
        self.assertEqual(rows[0]["url"], "https://media.partner.example/31.m3u8")
        self.assertEqual(partner.sports_events(), [])
        self.assertEqual(adapter.paths, ["tv.php", "channels.php"])

    def test_login_session_denial_does_not_expose_password(self):
        class Denied:
            def _authenticated(self, route, fields):
                raise PartnerAccessError("partner_login_rejected")
        with self.assertRaises(PartnerApiError) as failure:
            LmhdLoginPartner(Denied()).tv_channels()
        self.assertEqual(failure.exception.code, "partner_session_denied")

    def test_login_adapter_disabled_without_credentials(self):
        keys = {
            "POTV_LMHD_API_BASE_URL": "",
            "POTV_LMHD_SERVICE_USERNAME": "",
            "POTV_LMHD_SERVICE_PASSWORD": "",
            "POTV_LMHD_SERVICE_DEVICE": "",
        }
        with patch.dict(os.environ, keys):
            self.assertIsNone(LmhdLoginPartner.from_environment())

    def test_disabled_configuration_is_not_connected(self):
        with tempfile.TemporaryDirectory() as tmp:
            f = Path(tmp)/"approved-partner.json"
            f.write_text(json.dumps({"enabled": False,
                        "base_url": "https://api.partner.example/",
                        "token": "test", "device": "test"}))
            self.assertIsNone(LmhdPartner.from_file(str(f)))


if __name__ == "__main__":
    unittest.main(verbosity=2)
