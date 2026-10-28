"""Fail-closed NOVA snapshot retention when partner guide or AniList is down."""
import json
import tempfile
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest.mock import patch

from nova_catalog_sync import retain_recent_guide, synchronize

now = datetime.now(timezone.utc).replace(microsecond=0)
def program(title, start, end, **extra):
    return {"title": title, "starts_at": start.isoformat(),
            "ends_at": end.isoformat(), **extra}

active = program("Juego confirmado", now-timedelta(minutes=5),
                 now+timedelta(minutes=55),
                 stream_url="https://private.example/DO-NOT-LEAK")
next_up = program("Siguiente programa", now+timedelta(minutes=55),
                  now+timedelta(hours=2))
old = {"updated_at": (now-timedelta(minutes=20)).isoformat(),
       "now_next": [
           {"channel_id": "epg:1", "now": active, "next": next_up},
           {"channel_id": "removed", "now": active},
           {"channel_id": "epg:2", "now": program("Expired",
                now-timedelta(hours=3), now-timedelta(minutes=2))},
       ]}
channels = [{"id":"nova:1","epg_id":"epg:1","url":"https://example.org/1"},
            {"id":"nova:2","epg_id":"epg:2","url":"https://example.org/2"}]
kept = retain_recent_guide([], old, channels, now=now)
assert len(kept)==1 and kept[0]["channel_id"]=="epg:1", kept
assert kept[0]["now"]["title"]=="Juego confirmado"
assert "DO-NOT-LEAK" not in json.dumps(kept)
assert "stream_url" not in json.dumps(kept)
assert retain_recent_guide([], {**old,
    "updated_at":(now-timedelta(minutes=46)).isoformat()}, channels, now=now)==[]
# Rewriting the snapshot must NOT refresh cached EPG indefinitely.
assert retain_recent_guide([], {**old,
    "updated_at":now.isoformat(),
    "guide_seen_at":{"epg:1":(now-timedelta(minutes=46)).isoformat()}},
    channels, now=now)==[]
fresh = [{"channel_id":"epg:1", "now":program("Actual",
    now-timedelta(minutes=1),now+timedelta(minutes=59))}]
assert retain_recent_guide(fresh,old,channels,now=now)==fresh
assert retain_recent_guide([], {**old,"updated_at":"invalid"},channels,now=now)==[]

# A provider can respond successfully but send an expired NOW; it must not
# suppress the recent, still-valid cached guide for that same EPG ID.
stale_now = program("Caducado upstream", now-timedelta(hours=2),
                    now-timedelta(minutes=10),
                    stream_url="https://private.example/SHOULD-NOT-LEAK")
fallback = retain_recent_guide(
    [{"channel_id":"epg:1", "now":stale_now}], old, channels, now=now)
assert len(fallback)==1 and fallback[0]["now"]["title"]=="Juego confirmado", fallback
assert "SHOULD-NOT-LEAK" not in json.dumps(fallback)
# Keep only valid parts of a fresh row, without copying secret metadata.
mixed = retain_recent_guide(
    [{"channel_id":"epg:1", "now":active, "next":stale_now,
      "url":"https://private.example/SHOULD-NOT-LEAK"}],
    old, channels, now=now)
assert len(mixed)==1 and "next" not in mixed[0], mixed
assert "stream_url" not in json.dumps(mixed)
# A malformed fresh response cannot make EPG survive beyond the 45-minute TTL.
assert retain_recent_guide(
    [{"channel_id":"epg:1", "now":stale_now}],
    {**old, "updated_at":(now-timedelta(minutes=46)).isoformat()},
    channels, now=now)==[]
print("PASS: EPG retained only for active authorized channels within 45min")

class Service:
    def channels(self): return []
    def app_version(self): return {}
    def movies(self): return []
    def series(self): return []
    def anime(self): return []

with tempfile.TemporaryDirectory() as tmp:
    dest = Path(tmp)/"private.json"
    old["anime"] = [{"anilist_id":1234,"title":"Mapped anime"},
                    {"tmdb_id":999,"title":"Invalid mapping"}]
    old["movies"] = []
    old["series"] = []
    old["media_scan_offsets"] = {}
    dest.write_text(json.dumps(old),encoding="utf-8")
    with patch("nova_catalog_sync.normalize_channels",return_value=(channels,{})), \
         patch("nova_catalog_sync.enrich_stream_formats",return_value=(channels,{})), \
         patch("nova_catalog_sync.progressive_media",side_effect=[([],0,0),([],0,0)]), \
         patch("nova_catalog_sync.fetch_media_pages",side_effect=ValueError("temporary outage")), \
         patch("nova_catalog_sync.all_channel_guide",return_value=[]), \
         patch("nova_catalog_sync.write_media_index"):
        summary = synchronize(service=Service(),destination=dest,anime_map_file="mapped.json")
    saved = json.loads(dest.read_text(encoding="utf-8"))
    assert saved["anime"]==[{"anilist_id":1234,"title":"Mapped anime"}], saved["anime"]
    assert len(saved["now_next"])==1, saved["now_next"]
    assert saved["guide_seen_at"]["epg:1"]==old["updated_at"]
    assert summary["anime_catalog_mapped"]==1
print("PASS: sync outage does not erase valid mapped anime or fresh EPG")
