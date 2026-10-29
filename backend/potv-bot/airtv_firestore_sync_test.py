"""AirTV Firestore contract: pagination, normalization, privacy and atomic updates."""
import io
import json
import os
import tempfile
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

from airtv_firestore_sync import (
    channel_from_firestore, firestore_channels, public_url, write_snapshot,
)


def document(identifier, url, backup="", status="ACTIVO", menu="Noticias"):
    fields = {
        "NOMBRE": {"stringValue": "Noticias AirTV"},
        "URL": {"stringValue": url},
        "ESTADO": {"stringValue": status},
        "MENU": {"stringValue": menu},
        "PAIS": {"stringValue": "México"},
        "IMAGEN": {"stringValue": "https://images.partner.example/logo.png"},
    }
    if backup:
        fields["ENLACES"] = {"arrayValue": {
            "values": [{"stringValue": backup}]
        }}
    return {
        "name": "projects/example/databases/(default)/documents/channels/" + identifier,
        "fields": fields,
    }


primary = "https://cdn.partner.example/primary.m3u8"
secondary = "https://cdn.partner.example/secondary.m3u8"
channel = channel_from_firestore(document("uno", primary, secondary))
assert channel is not None and channel["name"] == "Noticias AirTV"
assert channel["url"] == primary
assert channel["backup_urls"] == [secondary]
assert channel["id"].startswith("airtv:")
assert channel["group"] == "Noticias | México"
assert channel_from_firestore(document("uno", primary, status="INACTIVO")) is None
assert channel_from_firestore(document("uno", "http://127.0.0.1/private")) is None
assert public_url("https://cdn.partner.example/hls.m3u8")
assert not public_url("http://192.168.1.10/signal")
assert not public_url("file:///tmp/fake")

seen = []


def fake_transport(req, timeout):
    assert req.get_header("Authorization") == "Bearer fixture"
    assert urlsplit(req.full_url).hostname == "firestore.googleapis.com"
    query = parse_qs(urlsplit(req.full_url).query)
    seen.append(query.get("pageToken"))
    if not query.get("pageToken"):
        response = {"documents": [document("uno", primary, secondary)],
                    "nextPageToken": "other"}
    else:
        response = {"documents": [
            document("uno", primary),
            document("dos", "https://cdn.partner.example/two.m3u8"),
        ]}
    return io.BytesIO(json.dumps(response).encode())


rows = firestore_channels("example-project", "fixture", transport=fake_transport)
assert len(rows) == 2 and seen == [None, ["other"]]
assert rows[0]["id"] != rows[1]["id"]
assert rows[0]["url"] == primary

with tempfile.TemporaryDirectory() as temp:
    location = Path(temp) / "snapshot.json"
    assert write_snapshot(location, rows) == 2
    revision = json.loads(location.read_text())["revision"]
    assert oct(location.stat().st_mode & 0o777) == "0o600"
    changed = [dict(row) for row in rows]
    changed[0]["url"] = "https://cdn.partner.example/rotated.m3u8"
    write_snapshot(location, changed)
    assert json.loads(location.read_text())["revision"] != revision
    assert json.loads(location.read_text())["channels"][0]["id"] == rows[0]["id"]

print("PASS AirTV Firestore mapping, page refresh, stable identity and atomic snapshot")
