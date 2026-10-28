"""EPG cannot remain live after its real end time, even from cached catalogs."""
from datetime import datetime, timedelta, timezone

from content_gateway import ContentGateway


def slot(title, start, end, **extra):
    return {"title": title, "starts_at": start.isoformat(),
            "ends_at": end.isoformat(), **extra}


fixed = datetime(2026, 10, 28, 12, 0, tzinfo=timezone.utc)
g = ContentGateway(sources=[], public_base="https://potv.example",
                   signing_secret=b"epg-fixture")
active = slot("Ahora real", fixed - timedelta(minutes=5),
              fixed + timedelta(minutes=55), stream_url="https://private.example")
upcoming = slot("Después", fixed + timedelta(minutes=55),
                fixed + timedelta(hours=2))
expired = slot("Ayer", fixed - timedelta(hours=3),
               fixed - timedelta(minutes=1))
naive = {"title": "Sin zona", "starts_at": "2026-10-28T11:00:00",
         "ends_at": "2026-10-28T13:00:00"}
future = slot("No es ahora", fixed + timedelta(hours=2),
              fixed + timedelta(hours=3))
long = slot("Duración absurda", fixed - timedelta(minutes=1),
            fixed + timedelta(hours=20))
raw = [
    {"channel_id": "valid", "now": active, "next": upcoming},
    {"channel_id": "expired", "now": expired},
    {"channel_id": "naive", "now": naive},
    {"channel_id": "future-now", "now": future},
    {"channel_id": "too-long", "now": long},
    {"channel_id": "past-next", "next": expired},
]
clean = g._guide_payload({"now_next": raw}, now=fixed)
assert len(clean) == 1 and clean[0]["channel_id"] == "valid", clean
assert clean[0]["current"]["title"] == "Ahora real"
assert clean[0]["next"]["title"] == "Después"
assert "stream_url" not in str(clean) and "private.example" not in str(clean)

# In-memory cached payloads are revalidated on EVERY subscriber response;
# the caller's cached object is not mutated.
now = datetime.now(timezone.utc)
old = slot("Ya terminó", now - timedelta(hours=2),
           now - timedelta(minutes=1))
live = slot("En curso", now - timedelta(minutes=5),
            now + timedelta(minutes=55))
cached = {"data": {"channels": [], "sports_channels": [],
                   "sports_events": [], "now_next": [
                       {"channel_id": "old", "current": old},
                       {"channel_id": "live", "current": live},
                   ]}}
fresh = g._resign_cached_catalog(cached)
assert [row["channel_id"] for row in fresh["data"]["now_next"]] == ["live"], fresh
assert len(cached["data"]["now_next"]) == 2, "cached source was mutated"
print("PASS: NOW/NEXT timezones, expired guides and cached refresh")
