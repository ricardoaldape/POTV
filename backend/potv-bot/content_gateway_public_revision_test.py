"""Public EPG revisions must change for real data, not signed URL TTL."""
from datetime import datetime, timedelta, timezone
from content_gateway import ContentGateway

revision = ContentGateway._public_catalog_revision
now = datetime.now(timezone.utc)
base = "https://potv.example/api/v1/content/stream/opaque-id"
channel = {"id": "channel-1", "name": "Canal Uno", "hls_url": base + "?expires=123&sig=a"}
guide = [{"channel_id": "epg-1", "current": {
    "title": "Partido A", "starts_at": now.isoformat(),
    "ends_at": (now + timedelta(hours=1)).isoformat()}}]
events = [{"id": "evt-1", "home": "A", "away": "B",
           "streams": [{"url": base + "?expires=123&sig=a"}]}]
original = revision([channel], guide, events)
assert original == revision([channel], guide, events)
rotated_signature = dict(channel, hls_url=base + "?expires=999&sig=b")
rotated_event = dict(events[0], streams=[{"url": base + "?expires=999&sig=b"}])
assert original == revision([rotated_signature], guide, [rotated_event]), (
    "Short-lived proxy signatures must not churn revision")
updated_guide = [{"channel_id": "epg-1", "current": dict(
    guide[0]["current"], title="Partido B")}]
assert original != revision([channel], updated_guide, events), (
    "Same EPG count but new programme must advance revision")
updated_channel = dict(channel, hls_url=base.replace("opaque-id", "new-target") + "?sig=c")
assert original != revision([updated_channel], guide, events), (
    "Upstream source rotation must advance revision")
updated_metadata = dict(channel, name="Canal Uno HD")
assert original != revision([updated_metadata], guide, events)
updated_event = dict(events[0], home="Equipo distinto")
assert original != revision([channel], guide, [updated_event])
assert len(original) == 20 and original.isalnum()
assert "opaque-id" not in original and "sig" not in original
print("PASS: public EPG revision changes on programme/source/event metadata, not proxy signature")
