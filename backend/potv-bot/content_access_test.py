"""POTV user subscriptions gate licensed video; never provider logins."""
from datetime import datetime, timezone, timedelta

from content_access import has_active_subscription, requires_vod_subscription

now = datetime(2026, 10, 15, 16, 0, tzinfo=timezone.utc)
future = (now + timedelta(days=2)).isoformat()
past = (now - timedelta(seconds=1)).isoformat()

for account in (None, {}, {"subscription_status": "free"},
                {"subscription_status": "pending", "subscription_expires_at": future},
                {"subscription_status": "expired", "subscription_expires_at": future},
                {"subscription_status": "active"},
                {"subscription_status": "active", "subscription_expires_at": past},
                {"subscription_status": "active", "subscription_expires_at": "garbage"},
                {"subscription_status": "active", "subscription_expires_at": "2027-01-01"}):
    assert not has_active_subscription(account, now=now), account

assert has_active_subscription({
    "subscription_status": "active", "subscription_expires_at": future
}, now=now)
assert has_active_subscription({
    "subscription_status": "active", "subscription_expires_at": "2026-10-16T00:00:00Z"
}, now=now)

class Gateway:
    lmhd_vod_enabled = False

gw = Gateway()
assert not requires_vod_subscription(gw, {})
assert requires_vod_subscription(gw, {"POTV_REQUIRE_VOD_SUBSCRIPTION": "true"})
assert requires_vod_subscription(gw, {"POTV_REQUIRE_VOD_SUBSCRIPTION": "1"})
gw.lmhd_vod_enabled = True
assert requires_vod_subscription(gw, {})
print("PASS: POTV subscription rejects free/expired/invalid users and gates paid media")
