"""NOVA's real 1.2.9 guide response is only published for exact EPG channels."""
import io
import json
from datetime import datetime, timedelta, timezone
from urllib.error import HTTPError
from urllib.parse import urlsplit

from nova_partner import NovaPartner, NovaPartnerError
from nova_catalog_sync import sports_guide


class Bytes(io.BytesIO):
    status = 200
    def __enter__(self):
        return self
    def __exit__(self, *args):
        self.close()


class FakeOpener:
    def __init__(self):
        self.calls = []
        self.deny = False

    def open(self, req, timeout=0):
        if self.deny:
            raise HTTPError(req.full_url, 403, "Forbidden", {}, None)
        assert req.method == "POST"
        assert urlsplit(req.full_url).path.endswith("/channels/guide/now-next")
        assert req.get_header("Authorization") == "Bearer test-token"
        assert req.get_header("Content-type") == "application/json"
        body = json.loads(req.data)
        self.calls.append(body["channel_ids"])
        now = datetime.now(timezone.utc).replace(microsecond=0)
        begin = (now - timedelta(minutes=15)).isoformat()
        end = (now + timedelta(minutes=45)).isoformat()
        result = []
        for cid in body["channel_ids"]:
            if cid == 100:
                result.append({
                    "channel_id": cid,
                    "now": {"title": "América vs Pumas",
                            "description": "En vivo", "start_time": begin,
                            "end_time": end, "is_live_event": True,
                            "stream_url": "https://secret.example/signed?token=SHOULD_NOT_LEAK"},
                    "next": {"title": "SportsCenter",
                             "start_time": end,
                             "end_time": (now + timedelta(hours=2)).isoformat()},
                })
            elif cid == 101:
                result.append({
                    "channel_id": cid,
                    "now": {"title": "Repeats",
                            "start_time": "2020-01-01T10:00:00+00:00",
                            "end_time": "2020-01-01T11:00:00+00:00"},
                })
            else:
                result.append({"channel_id": cid, "now": None, "next": None})
        # An unexpected channel must never be accepted.
        result.append({"channel_id": 9999, "now": {
            "title": "Spoof", "start_time": begin, "end_time": end}})
        return Bytes(json.dumps(result).encode())


opener=FakeOpener()
service=NovaPartner(base_url="https://partner.example/api/v1/",
                    access_token="test-token",opener=opener)
for bad in ([], [0], [-1], ["123"], list(range(1,42))):
    try:
        service.sports_now_next(bad)
        raise AssertionError("invalid ids accepted")
    except ValueError:
        pass
assert service.sports_now_next([100])[0]["channel_id"]==100

snapshot=[
    {"id":"nova:100","epg_id":"777","name":"TUDN","country":"MX",
     "is_sports":True},
    {"id":"nova:101","epg_id":"778","name":"ESPN","country":"MX",
     "is_sports":True},
    {"id":"nova:102","epg_id":"779","name":"Drama","country":"MX",
     "is_sports":False},
    {"id":"nova:9999","epg_id":"","name":"Missing EPG","country":"MX",
     "is_sports":True},
]
rows=sports_guide(service,snapshot)
assert len(rows)==1, rows
assert rows[0]["channel_id"]=="777",rows
assert rows[0]["now"]["title"]=="América vs Pumas"
assert rows[0]["next"]["title"]=="SportsCenter"
assert "SHOULD_NOT_LEAK" not in json.dumps(rows)
assert not any(row.get("channel_id")=="9999" for row in rows)
assert 102 not in opener.calls[-1]
assert 9999 not in opener.calls[-1]
print("PASS: bounded NOVA 1.2.9 POST EPG maps only to same published EPG channel")

opener.deny=True
try:
    service.sports_now_next([100])
    raise AssertionError("provider denial bypassed")
except NovaPartnerError as error:
    assert error.code=="upstream_denied"
assert sports_guide(service,snapshot)==[]
print("PASS: upstream entitlement denial fails closed and does not affect channels")
