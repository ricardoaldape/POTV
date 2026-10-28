"""Regression: subscriber receives NOVA, public API remains starter-only."""
import json
import os
import tempfile
from unittest.mock import patch
from datetime import datetime, timedelta, timezone
from urllib.parse import urlsplit,parse_qs
from content_gateway import ContentGateway
from nova_catalog_sync import normalize_channels

class FixtureGateway(ContentGateway):
    def _build_catalog(self):
        return {"data":{
            "revision": "starter",
            "channels":[{"id":"starter","name":"POTV Starter","hls_url":"https://potv.example/abc"}],
            "sports_channels":[],"sports_events":[],"now_next":[],"source_failures":0
        }}

with tempfile.TemporaryDirectory() as tmp:
    path = os.path.join(tmp, "nova.json")
    with open(path, "w") as fh:
        json.dump({"revision":"nova-v1","anime":[
            {"anilist_id":195539,"tmdb_id":326788,
             "title":"Cyberpunk: Edgerunners 2","year":"2026"}
        ],"now_next":[
            {"channel_id":"nfl","now":{"title":"Football previo",
             "starts_at":(datetime.now(timezone.utc)-timedelta(minutes=10)).isoformat(),
             "ends_at":(datetime.now(timezone.utc)+timedelta(minutes=50)).isoformat()}},
            {"channel_id":"orphan-from-removed-channel","now":{
             "title":"Never show",
             "starts_at":(datetime.now(timezone.utc)-timedelta(minutes=10)).isoformat(),
             "ends_at":(datetime.now(timezone.utc)+timedelta(minutes=50)).isoformat()}},
        ],"channels":[
            {"id":"nova:1", "name":"NFL Network", "url":"https://nova.example/nfl.m3u8",
             "group":"Deportes", "epg_id":"nfl", "format":"hls", "backup_urls":[
                 "https://nova-b.example/nfl2.m3u8"]},
            {"id":"nova:2", "name":"Canal MX", "url":"http://nova.example/mx.ts",
             "group":"General", "epg_id":"mx", "backup_urls":[]},
            {"id":"nova:3", "name":"XXX Adult", "url":"https://nova.example/x.m3u8",
             "group":"Adultos", "epg_id":"x", "backup_urls":[]},
        ]}, fh)
    with patch.dict(os.environ, {
        "POTV_NOVA_SERVICE_FILE":"","POTV_NOVA_SYNC_FILE":path,
        "POTV_NOVA_LIVE_ENABLED":"true",
    }):
        g=FixtureGateway(sources=["https://fixture.example"],public_base="https://potv.example",
                         signing_secret=b"subscriber-test")
        assert len(g.catalog()["data"]["channels"])==1
        g.nova_live_enabled=True  # Licensed and customer-entitled fixture only.
        private=g.catalog_for_subscriber()
        channels=private["data"]["channels"]
        sports=private["data"]["sports_channels"]
        assert len(channels)==3, channels
        assert len(sports)==1,sports
        assert private["data"]["anime"][0]["anilist_id"] == 195539
        assert "anime" not in g.catalog()["data"], "NOVA anime must remain subscriber-only"
        assert private["data"]["now_next"][0]["channel_id"] == "nfl"
        assert private["data"]["now_next"][0]["current"]["title"] == "Football previo"
        assert len(private["data"]["now_next"]) == 1, "orphan EPG published"
        assert not g.catalog()["data"]["now_next"], "private sports guide leaked publicly"
        assert private["data"]["sports_events"] == [], "program guide is not a verified event feed"
        assert "NFL Network" in [s["name"] for s in sports]
        assert channels[0]["name"]=="POTV Starter"
        assert all("nova.example" not in json.dumps(r) for r in channels)
        assert all("nova-b.example" not in json.dumps(r) for r in channels)
        nfl=sports[0]
        assert nfl["hls_url"].startswith("https://potv.example/api/v1/content/stream/")
        assert len(nfl.get("backup_urls") or [])==1
        assert "format=hls" in nfl["hls_url"]
        assert "s" in parse_qs(urlsplit(nfl["hls_url"]).query)
        assert len(g.catalog()["data"]["channels"])==1
        cached=g.catalog_for_subscriber()["data"]
        assert len(cached["channels"])==3
        cached_nfl=next(row for row in cached["sports_channels"]
                        if row["name"]=="NFL Network")
        assert "format=hls" in cached_nfl["hls_url"]
        # Simulate backend restart: the media proxy must be able to re-register
        # the signed channel URL from the protected local feed.
        target_id=urlsplit(nfl["hls_url"]).path.rsplit("/",1)[-1]
        g._targets.clear()
        g._hydrate_target(target_id)
        assert target_id in g._targets
        assert g._targets[target_id][0] == "https://nova.example/nfl.m3u8"
        g.nova_live_enabled=False
        assert len(g.catalog_for_subscriber()["data"]["channels"])==1

    rows,counts=normalize_channels([
        {"id":1,"name":"Canal AR","country":"AR","region":"latam","stream_url":"https://test.example/stream"},
        {"id":2,"name":"NFL Network","country":"US","region":"usa","category":"Deportes","stream_url":"https://test.example/nfl"},
        {"id":3,"name":"Canal Mexicano","country":"MX","region":"mx","category":"General","stream_url":"https://test.example/mx"},
        {"id":4,"name":"Canal Adulto","country":"MX","region":"mx","category":"adultos","stream_url":"https://test.example/xxx"}
    ],limit=100)
    assert len(rows)==2,rows
    assert rows[0]["name"]=="NFL Network"
    assert rows[1]["name"]=="Canal Mexicano"

print("PASS: paid NOVA live + NFL Network, backups, adult/AR filtering, private vs public response")
