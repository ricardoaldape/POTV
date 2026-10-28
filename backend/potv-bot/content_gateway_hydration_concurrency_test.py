"""A burst of signed stream requests must not OOM the POTV account API."""
from concurrent.futures import ThreadPoolExecutor
import json
import os
import tempfile
import threading
import time
from unittest.mock import patch

from content_gateway import ContentGateway


class FixtureGateway(ContentGateway):
    builds = 0

    def _build_catalog(self):
        with self._lock:
            self.builds += 1
        # Model an expensive provider catalog while other viewers connect.
        time.sleep(.06)
        return {"data": {
            "revision": "starter",
            "channels": [{"id": "starter", "name": "Starter",
                          "hls_url": "https://potv.example/starter.m3u8"}],
            "sports_channels": [], "now_next": [], "sports_events": [],
        }}


with tempfile.TemporaryDirectory() as tmp:
    feed = os.path.join(tmp, "nova-private.json")
    url = "https://media.example/nfl-network/live.m3u8"
    with open(feed, "w", encoding="utf-8") as output:
        json.dump({
            "revision":"test", "channels":[{
                "id":"nova:123","name":"NFL Network","group":"Sports",
                "epg_id":"nfl123", "url":url,"backup_urls":[],
                "country":"MX","is_sports":True,
            }],
        }, output)
    with patch.dict(os.environ, {
        "POTV_NOVA_SERVICE_FILE": "",
        "POTV_NOVA_SYNC_FILE": feed,
        "POTV_NOVA_LIVE_ENABLED": "true",
    }):
        g = FixtureGateway(
            sources=["https://fixture.example/"],
            public_base="https://potv.example",
            signing_secret=b"concurrency-test",
        )
        g.nova_live_enabled = True
        target = g._register_target(url)
        g._targets.clear()
        g._target_last_signed.clear()
        ready = threading.Barrier(12)
        def viewer(index):
            ready.wait(timeout=4)
            g._hydrate_target(target)
            return target in g._targets
        with ThreadPoolExecutor(max_workers=12) as threads:
            found = list(threads.map(viewer, range(12)))
        assert all(found), found
        assert g.builds == 1, "Concurrent viewers rebuilt catalog too many times"
        # A signed HLS segment from a prior process cannot be reconstituted
        # from the channel catalog. A miss must NOT trigger repeated full
        # 7,000-channel rebuilds.
        unknown = "0123456789abcdef0123456789abcdef"
        g._hydrate_target(unknown)
        assert g.builds == 1
        print("PASS: 12 simultaneous viewers hydrate private channels only once")
