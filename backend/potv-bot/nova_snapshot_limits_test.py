"""Regression: progressive VOD growth must not silently erase private TV."""
import json
import tempfile
import time
from pathlib import Path
from unittest.mock import patch

import nova_catalog_sync as sync
from content_gateway import ContentGateway
from nova_partner import NovaPartnerError
from nova_snapshot_limits import MAX_NOVA_SNAPSHOT_BYTES

assert MAX_NOVA_SNAPSHOT_BYTES == sync.MAX_NOVA_SNAPSHOT_BYTES
assert MAX_NOVA_SNAPSHOT_BYTES >= 13 * 1024 * 1024


class FixtureGateway(ContentGateway):
    def _build_catalog(self):
        return {"data": {"revision": "starter", "channels": [],
                         "sports_channels": [], "sports_events": [],
                         "now_next": []}}


class Service:
    def channels(self):
        return []

    def app_version(self):
        return {}

    def movies(self, **kwargs):
        return []

    def series(self, **kwargs):
        return []


with tempfile.TemporaryDirectory() as folder:
    destination = Path(folder) / "private.json"
    private = {"revision": "nova-licensed", "channels": [
        {"id": "nova:1", "name": "Canal autorizado", "group": "TV",
         "url": "https://partner.example/live.m3u8", "epg_id": "epg:1"}
    ]}
    destination.write_text(json.dumps(private), encoding="utf-8")
    gateway = FixtureGateway(sources=["https://fixture.example"],
                             public_base="https://potv.example",
                             signing_secret=b"snapshot-size-test")
    gateway.nova_live_enabled = True
    gateway.nova_sync_file = str(destination)

    # An otherwise valid 13 MiB private catalog used to be discarded at 12 MiB.
    with patch("content_gateway.os.path.getsize", return_value=13 * 1024 * 1024):
        result = gateway.catalog_for_subscriber()
    assert len(result["data"]["channels"]) == 1, result

    # If a future provider response exceeds the hard cap, retain the last
    # known subscriber-only catalog rather than falling back to public TV.
    gateway._nova_subscriber_catalog_at = time.monotonic() - gateway.refresh_seconds - 1
    with patch("content_gateway.os.path.getsize", return_value=MAX_NOVA_SNAPSHOT_BYTES + 1):
        held = gateway.catalog_for_subscriber()
    assert len(held["data"]["channels"]) == 1, held
    assert "partner.example" not in json.dumps(held)

    # A cold start must fail closed when the private snapshot is oversized.
    fresh = FixtureGateway(sources=["https://fixture.example"],
                           signing_secret=b"snapshot-cold-start")
    fresh.nova_live_enabled = True
    fresh.nova_sync_file = str(destination)
    with patch("content_gateway.os.path.getsize", return_value=MAX_NOVA_SNAPSHOT_BYTES + 1):
        assert fresh.catalog_for_subscriber()["data"]["channels"] == []

    # The sync must never replace the last good JSON or SQLite index with
    # a payload that the API would refuse to read.
    previous = {"channels": private["channels"], "movies": [],
                "series": [], "anime": [], "now_next": [],
                "media_scan_offsets": {"movies": 0, "series": 0}}
    destination.write_text(json.dumps(previous), encoding="utf-8")
    old_bytes = destination.read_bytes()
    index = Path(str(destination) + ".media.sqlite3")
    index.write_bytes(b"previous-private-index")
    channel = private["channels"][0]
    oversized_media = [{"tmdb_id": 123, "title": "Película",
                        "overview": "A" * 1200}]
    with patch.object(sync, "MAX_NOVA_SNAPSHOT_BYTES", 512), \
         patch.object(sync, "normalize_channels", return_value=([channel], {})), \
         patch.object(sync, "enrich_stream_formats", return_value=([channel], {})), \
         patch.object(sync, "progressive_media", side_effect=[
             (oversized_media, 0, 1), ([], 0, 0)]), \
         patch.object(sync, "all_channel_guide", return_value=[]):
        try:
            sync.synchronize(service=Service(), destination=destination)
            raise AssertionError("Oversized snapshot was published")
        except NovaPartnerError as exc:
            assert str(exc) == "nova_snapshot_too_large"
    assert destination.read_bytes() == old_bytes
    assert index.read_bytes() == b"previous-private-index"
    assert not list(Path(folder).glob(".nova-sync-*"))

print("PASS: 13 MiB catalog retained, oversized fallback safe, atomic oversize rejection")
