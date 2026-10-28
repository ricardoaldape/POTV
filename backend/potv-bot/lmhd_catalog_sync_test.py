"""LMHD automatic catalog sync, freshness, revocation and POTV privacy."""
import json
import os
import tempfile
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest.mock import patch

from content_gateway import ContentGateway
from lmhd_partner import PartnerApiError
import lmhd_catalog_sync as sync


class Fixture:
    def __init__(self):
        self.current = "Uno"
        self.calls = 0

    def tv_channels(self):
        self.calls += 1
        return [{
            "name": self.current,
            "url": "https://media.partner.example/live/" + self.current + ".m3u8",
            "epg_id": "lmhd:3", "provider_id": "3", "group": "Deportes",
            "epg": [{
                "title": "Transmisión " + self.current,
                "starts_at": (datetime.now(timezone.utc) -
                              timedelta(minutes=2)).isoformat(),
                "ends_at": (datetime.now(timezone.utc) +
                            timedelta(minutes=58)).isoformat(),
            }],
        }]

    def sports_events(self):
        return []

    def movie_sources(self, **kwargs):
        return []

    def episode_sources(self, **kwargs):
        return []


with tempfile.TemporaryDirectory() as tmp:
    fixture = Fixture()
    snapshot = Path(tmp) / "lmhd-catalog.json"
    assert sync.write_snapshot(snapshot, fixture) == (1, 0)
    assert (snapshot.stat().st_mode & 0o777) == 0o600
    assert "media.partner.example" in snapshot.read_text()
    public = ContentGateway(
        sources=[], public_base="https://potv.example",
        signing_secret=b"authorized-lmhd-snapshot-test",
    )
    public.lmhd = fixture
    public.lmhd_sync_file = str(snapshot)
    public.lmhd_live_catalog_enabled = True
    assert public.catalog()["data"]["channels"] == []
    entitled = public.catalog_for_subscriber()["data"]
    assert [x["name"] for x in entitled["channels"]] == ["Uno"]
    assert entitled["now_next"][0]["current"]["title"] == "Transmisión Uno"
    assert "media.partner.example" not in str(entitled)
    # Real-time snapshot was used; no new provider HTTP request on a view.
    assert fixture.calls == 1
    fixture.current = "Dos"
    assert sync.write_snapshot(snapshot, fixture) == (1, 0)
    public.refresh_seconds = 0
    changed = public.catalog_for_subscriber()["data"]
    assert [x["name"] for x in changed["channels"]] == ["Dos"]
    assert changed["channels"][0]["id"] == entitled["channels"][0]["id"]
    assert changed["revision"] != entitled["revision"]
    # Old snapshots must never be used once scheduled refresh stops.
    os.utime(snapshot, (time.time() - 800, time.time() - 800))
    fixture.current = "Tres"
    stale = public.catalog_for_subscriber()["data"]
    assert [x["name"] for x in stale["channels"]] == ["Tres"]
    assert fixture.calls == 3

    # A hard provider denial atomically revokes stale media sources.
    config = Path(tmp) / "provider.json"
    config.write_text("{}")
    def reject(_):
        raise PartnerApiError("partner_session_denied")
    with patch.dict(os.environ, {
        "POTV_LMHD_SERVICE_FILE": str(config),
        "POTV_LMHD_SYNC_FILE": str(snapshot),
    }), patch.object(sync.LmhdPartner, "from_file", side_effect=reject):
        assert sync.run() == 1
    assert not snapshot.exists()
    # Dedicated rotating-login credentials (already supported by the gateway)
    # must be usable by the 5-minute sync as well as static token files.
    fixture.current = "Con login"
    with patch.dict(os.environ, {
        "POTV_LMHD_SERVICE_FILE": "",
        "POTV_LMHD_SYNC_FILE": str(snapshot),
    }), patch.object(sync.LmhdLoginPartner, "from_environment",
                    return_value=fixture):
        assert sync.run() == 0
    assert json.loads(snapshot.read_text())["channels"][0]["name"] == "Con login"
    snapshot.unlink()
    # Invalid, absent or disabled credentials never create a public catalog.
    with patch.dict(os.environ, {
        "POTV_LMHD_SERVICE_FILE": str(Path(tmp) / "absent.json"),
        "POTV_LMHD_SYNC_FILE": str(snapshot),
    }):
        assert sync.run() == 0
    assert not snapshot.exists()

print("PASS: automatic LMHD changes, entitlement, EPG, stable IDs, 0600, no stale URL, revocation")
