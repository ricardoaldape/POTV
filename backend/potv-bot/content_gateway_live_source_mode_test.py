"""Offline regression tests for independently merging licensed TV catalogs."""
import os
from unittest.mock import patch

from content_gateway import ContentGateway


class FixturesGateway(ContentGateway):
    def _m3u_inventory(self, source):
        name = "Channel One" if "one" in source else "NFL Network"
        return {"live": [{
            "name": name,
            "group": "TV" if "one" in source else "American Football",
            "url": "https://media.example.com/" + (
                "one.m3u8" if "one" in source else "nfl.m3u8"
            ),
        }]}

    def _metadata(self):
        return {}


sources = ["https://provider-one.example.com/live.m3u",
           "https://provider-two.example.com/live.m3u"]

with patch.dict(os.environ, {"POTV_CONTENT_LIVE_SOURCE_MODE": "merge"}):
    gateway = FixturesGateway(sources=sources, source_mode="failover", signing_secret=b"test")
    rows = gateway._build_catalog()["data"]["sports_channels"]
    names = [row["name"] for row in rows]
    assert "NFL Network" in names, names
    assert gateway.live_source_mode == "merge"
    channels = gateway._build_catalog()["data"]["channels"]
    assert len(channels) >= 2, channels

with patch.dict(os.environ, {"POTV_CONTENT_LIVE_SOURCE_MODE": "failover"}):
    gateway = FixturesGateway(sources=sources, source_mode="failover", signing_secret=b"test")
    channels = gateway._build_catalog()["data"]["channels"]
    names = [row["name"] for row in channels]
    assert "NFL Network" not in names, names
    assert gateway.live_source_mode == "failover"

with patch.dict(os.environ, {"POTV_CONTENT_LIVE_SOURCE_MODE": "invalid"}):
    gateway = FixturesGateway(sources=sources, source_mode="failover", signing_secret=b"test")
    assert gateway.live_source_mode == "failover"

print("PASS: live-TV merge independent of VOD failover, with backwards-compatible default")
