"""Kino/Stremio Live API interoperability contract tests (synthetic data)."""
import io
import json
import tempfile
import unittest
from pathlib import Path
from urllib.parse import urlsplit

from stremio_live_partner import StremioLivePartner, StremioLiveError


class Reply(io.BytesIO):
    def __init__(self,url,data):
        super().__init__(json.dumps(data).encode("utf8"))
        self.url=url

    def geturl(self):
        return self.url


class FakeOpener:
    def __init__(self):
        self.calls=[]

    def open(self,request,timeout=7):
        url=request.full_url
        self.calls.append(url)
        path=urlsplit(url).path
        if path.endswith("/manifest.json"):
            return Reply(url,{
                "id":"partner.live","types":["tv"],
                "resources":["catalog","meta","stream"],
                "catalogs":[{"type":"tv","id":"potv-approved"}]
            })
        if path.endswith("/catalog/tv/potv-approved.json"):
            return Reply(url,{"metas":[
                {"type":"tv","id":"mx-1","name":"Canal México",
                 "poster":"https://images.partner.example/1.png"},
                {"type":"tv","id":"mx-2","name":"Canal No Autorizado"},
                {"type":"tv","id":"mx-1","name":"Repetido"}
            ]})
        if path.endswith("/stream/tv/mx-1.json"):
            return Reply(url,{"streams":[
                {"url":"https://media.partner.example/live/one.m3u8"},
                {"url":"https://ads.tracker.example/watch"},
                {"url":"https://media.partner.example/live/one.m3u8"},
                {"url":"https://media.partner.example/live/backup.m3u8"}
            ]})
        raise AssertionError("unsolicited_api_request")


class StremioBridgeTest(unittest.TestCase):
    def setUp(self):
        self.opener=FakeOpener()
        self.api=StremioLivePartner(
            manifest_url="https://addon.partner.example/manifest.json",
            catalog_id="potv-approved",
            allowed_ids=["mx-1"],
            allowed_stream_hosts=["media.partner.example"],
            group="TV México",
            opener=self.opener,
        )

    def test_imports_only_allowlisted_channel_and_hosts(self):
        result=self.api.channels()
        self.assertEqual(len(result),1)
        self.assertEqual(result[0]["name"],"Canal México")
        self.assertEqual(result[0]["group"],"TV México")
        self.assertEqual(len(result[0]["backups"]),1)
        self.assertNotIn("ads.tracker.example",str(result))
        self.assertFalse(any("mx-2" in c for c in self.opener.calls))

    def test_reuses_cached_catalog_without_new_requests(self):
        self.api.channels()
        seen=len(self.opener.calls)
        self.api.channels()
        self.assertEqual(len(self.opener.calls),seen)

    def test_requires_explicit_allowlist_and_https(self):
        for cfg in [
            {"manifest_url":"http://addon.partner.example/manifest.json",
             "allowed_ids":["mx-1"],"allowed_stream_hosts":["media.partner.example"]},
            {"manifest_url":"https://addon.partner.example/manifest.json",
             "allowed_ids":[],"allowed_stream_hosts":["media.partner.example"]},
            {"manifest_url":"https://addon.partner.example/manifest.json",
             "allowed_ids":["mx-1"],"allowed_stream_hosts":[]},
        ]:
            with self.assertRaises(ValueError):
                StremioLivePartner(catalog_id="potv-approved",**cfg)

    def test_only_enabled_json_file_activates(self):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/"addon.json"
            path.write_text(json.dumps({"enabled":False}))
            self.assertIsNone(StremioLivePartner.from_file(str(path)))


if __name__ == "__main__":
    unittest.main(verbosity=2)
