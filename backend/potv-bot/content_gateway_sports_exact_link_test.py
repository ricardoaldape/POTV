"""No guessed SportsHub events; link only to an authorized exact channel."""
from urllib.parse import urlsplit
from content_gateway import ContentGateway

g = ContentGateway(sources=[], public_base="https://potv.example",
                   signing_secret=b"fixture-only")
tid = g._register_target("https://media.partner.example/espn.m3u8")
signed = g._proxy_url(tid)
sports = [{"id": "sport-1", "epg_id": "espn-mx", "hls_url": signed}]
base = {"sport": "Fútbol", "competition": "Liga MX", "home": "A",
        "away": "B", "starts_at": "2026-11-01T20:00:00Z"}

def event(event_id, **extra):
    return dict(base, id=event_id, **extra)

invalid_time = event("invalid-time", channel_id="sport-1")
invalid_time["starts_at"] = "bad"
naive_time = event("no-timezone", channel_id="sport-1")
naive_time["starts_at"] = "2026-11-01T20:00:00"
raw = [
    event("exact-id", channel_id="sport-1"),
    event("exact-epg", epg_id="espn-mx"),
    event("unknown", channel_id="sport-2"),
    event("guessed", channel="ESPN"),
    invalid_time,
    naive_time,
]
payload = g._events_payload({"sports_events": raw}, sports_channels=sports)
assert [row["id"] for row in payload] == ["exact-id", "exact-epg"], payload
assert all(row["streams"] == [{"url": signed}] for row in payload)
assert all(g._validate_signature(tid, urlsplit(row["streams"][0]["url"]).query)
           for row in payload)

# Ambiguous EPG mapping must not pick one of two providers.
second = dict(sports[0], id="sport-2")
assert g._events_payload({"sports_events": [event("ambiguous", epg_id="espn-mx")]},
                         sports_channels=[sports[0], second]) == []

# Explicit, authorized event stream wins over channel fallback; cached
# input is never mutated or expanded on subsequent catalog refreshes.
direct = "https://media.partner.example/event/fixture.m3u8"
input_streams = [direct]
metadata = {"sports_events": [event("direct", channel_id="sport-1",
                                   stream_url=direct, streams=input_streams)]}
first = g._events_payload(metadata, sports_channels=sports)
second = g._events_payload(metadata, sports_channels=sports)
assert len(first) == len(second) == 1
assert len(first[0]["streams"]) == len(second[0]["streams"]) == 1
assert input_streams == [direct], input_streams
assert first[0]["streams"][0]["url"] != signed
assert "media.partner.example" not in str(first)
print("PASS: exact SportsHub links, ambiguous/invalid rejection, immutable inputs")