"""AirTV is never public, signs primary and backups, and follows refreshes."""
import json
import os
import tempfile
import time
from pathlib import Path

from airtv_firestore_sync import channel_from_firestore, write_snapshot
from content_gateway import ContentGateway


def airtv_row(raw_url, backup=None):
    fields = {
        "NOMBRE": {"stringValue": "Noticias AirTV"},
        "URL": {"stringValue": raw_url},
        "MENU": {"stringValue": "Noticias"},
        "ESTADO": {"stringValue": "Activo"},
    }
    if backup:
        fields["ENLACES"] = {"arrayValue": {
            "values": [{"stringValue": backup}]
        }}
    return channel_from_firestore({
        "name": "projects/demo/databases/(default)/documents/channels/ID123",
        "fields": fields,
    })


with tempfile.TemporaryDirectory() as temp:
    snapshot = str(Path(temp) / "airtv.json")
    first = "https://airtv-source.example/live/ch.m3u8"
    backup = "https://airtv-source.example/live/ch2.m3u8"
    write_snapshot(snapshot, [airtv_row(first, backup)])

    gateway = ContentGateway(sources=[], public_base="https://potv.example",
                             signing_secret=b"fixture-airtv-key")
    gateway.lmhd = None
    gateway.airtv_sync_file = snapshot
    gateway.airtv_live_enabled = True
    gateway.nova_live_enabled = False
    assert gateway.configured

    public = gateway.catalog(force=True)["data"]
    assert not public["channels"] and not public["sports_channels"]
    subscribed = gateway.catalog_for_subscriber()["data"]
    assert len(subscribed["channels"]) == 1
    one = subscribed["channels"][0]
    assert one["id"].startswith("airtv:")
    assert one["hls_url"].startswith("https://potv.example/api/v1/content/stream/")
    assert len(one["backup_urls"]) == 1
    assert "format=hls" in one["hls_url"]
    assert first not in json.dumps(subscribed) and backup not in json.dumps(subscribed)
    assert subscribed["revision"] != public["revision"]

    # A normal cache refresh tracks changed upstream URLs without losing
    # a channel ID or displaying stale signed links.
    rotated = "https://airtv-source.example/live/rotated.m3u8"
    write_snapshot(snapshot, [airtv_row(rotated)])
    gateway._nova_subscriber_catalog = None
    next_data = gateway.catalog_for_subscriber()["data"]
    assert next_data["channels"][0]["id"] == one["id"]
    assert next_data["channels"][0]["hls_url"] != one["hls_url"]
    assert next_data["revision"] != subscribed["revision"]

    os.utime(snapshot, (time.time() - 2000, time.time() - 2000))
    gateway._nova_subscriber_catalog = None
    expired = gateway.catalog_for_subscriber()["data"]
    assert not expired["channels"], "stale AirTV stream survived a failed sync"
    assert not gateway.catalog(force=True)["data"]["channels"]

print("PASS AirTV private catalog, signed playback, rotation and expiry")
