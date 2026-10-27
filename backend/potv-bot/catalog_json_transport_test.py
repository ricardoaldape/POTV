"""Offline regression: 4MB catalog is compressed only when negotiated."""
import gzip
import json
from catalog_json_transport import accepts_gzip, encode_catalog

payload = {
    "data": {
        "revision": "rev-1",
        "channels": [
            {"id": f"nova:{i}", "name": f"Deportes México {i}",
             "hls_url": f"https://potv.fxqubit.com/api/v1/content/stream/{i}?s=fixture"}
            for i in range(12000)
        ],
        "anime": [{"anilist_id": 195539, "title": "Cyberpunk: Edgerunners 2"}],
    }
}
raw, flag = encode_catalog(payload, "")
assert not flag
assert json.loads(raw)["data"]["anime"][0]["anilist_id"] == 195539
compressed, flag = encode_catalog(payload, "br, gzip;q=1.0")
assert flag
assert len(compressed) < len(raw) * 0.5, (len(compressed), len(raw))
assert gzip.decompress(compressed) == raw
assert accepts_gzip("gzip;q=0") is False
assert accepts_gzip("GZIP;q=0.5") is True
assert accepts_gzip("gzip;q=not-a-number") is False
assert accepts_gzip("br") is False
for header in ("gzip;q=0", "br", ""):
    blob, enabled = encode_catalog(payload, header)
    assert not enabled and blob == raw
small, enabled = encode_catalog({"ok": True}, "gzip")
assert not enabled and json.loads(small) == {"ok": True}
print("PASS: large catalog gzip, Unicode, q-values, small response and exact JSON")
