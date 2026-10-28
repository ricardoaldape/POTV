"""Empty or malformed private sync must not erase the last licensed lineup."""
import json
import tempfile
import time
from pathlib import Path
from urllib.parse import urlsplit

from content_gateway import ContentGateway


class FixtureGateway(ContentGateway):
    def _build_catalog(self):
        return {"data": {"revision": "public", "channels": [],
                         "sports_channels": [], "sports_events": [],
                         "now_next": []}}


with tempfile.TemporaryDirectory() as folder:
    destination = Path(folder) / "nova.json"
    valid = {"revision": "licensed", "channels": [
        {"name": "Canal autorizado", "group": "TV", "epg_id": "epg:1",
         "url": "https://cdn.example/live.m3u8", "format": "hls"}
    ]}
    destination.write_text(json.dumps(valid), encoding="utf-8")
    gateway = FixtureGateway(sources=["https://fixture.example"],
                             public_base="https://potv.example",
                             signing_secret=b"private-retention-test")
    gateway.nova_live_enabled = True
    gateway.nova_sync_file = str(destination)
    first = gateway.catalog_for_subscriber()
    assert len(first["data"]["channels"]) == 1
    assert "cdn.example" not in json.dumps(first)
    original_url = first["data"]["channels"][0]["hls_url"]
    assert urlsplit(original_url).path.startswith("/api/v1/content/stream/")

    # A successfully parsed but empty upstream snapshot is an outage, not
    # permission to replace the subscriber's previously valid private lineup.
    for broken in ({"revision": "empty", "channels": []},
                   {"revision": "invalid", "channels": "not-a-list"},
                   {"revision": "missing"}):
        destination.write_text(json.dumps(broken), encoding="utf-8")
        gateway._nova_subscriber_catalog_at = time.monotonic() - gateway.refresh_seconds - 1
        retained = gateway.catalog_for_subscriber()
        assert len(retained["data"]["channels"]) == 1, broken
        signed = retained["data"]["channels"][0]["hls_url"]
        assert gateway._validate_signature(
            urlsplit(signed).path.rsplit("/", 1)[-1], urlsplit(signed).query)
        assert "cdn.example" not in json.dumps(retained)

    # A cold start cannot manufacture premium access from an empty snapshot.
    fresh = FixtureGateway(sources=["https://fixture.example"],
                           signing_secret=b"cold-start-test")
    fresh.nova_live_enabled = True
    fresh.nova_sync_file = str(destination)
    assert fresh.catalog_for_subscriber()["data"]["channels"] == []

print("PASS: empty/malformed NOVA snapshot retains cached subscriber lineup; cold start fails closed")
