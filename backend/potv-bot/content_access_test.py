"""POTV user subscriptions gate licensed video; never provider logins."""
from datetime import datetime, timezone, timedelta

from content_access import has_active_subscription, requires_vod_subscription, catalog_access_status

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
    "subscription_status": "trial", "subscription_expires_at": future
}, now=now)
assert not has_active_subscription({
    "subscription_status": "trial", "subscription_expires_at": past
}, now=now)
assert has_active_subscription({
    "subscription_status": "active", "subscription_expires_at": "2026-10-16T00:00:00Z"
}, now=now)

class Gateway:
    lmhd_vod_enabled = False
    nova_vod_enabled = False

gw = Gateway()
assert not requires_vod_subscription(gw, {})
assert requires_vod_subscription(gw, {"POTV_REQUIRE_VOD_SUBSCRIPTION": "true"})
assert requires_vod_subscription(gw, {"POTV_REQUIRE_VOD_SUBSCRIPTION": "1"})
gw.nova_vod_enabled = True
assert requires_vod_subscription(gw, {})
gw.nova_vod_enabled = False
gw.lmhd_vod_enabled = True
assert requires_vod_subscription(gw, {})
print("PASS: POTV subscription rejects free/expired/invalid users and gates paid media")

# Public starter catalog also contains short-lived signed stream URLs.
# Fail closed for anonymous, forged, expired, and pending sessions.
active = {"subscription_status": "active", "subscription_expires_at": future}
trial = {"subscription_status": "trial", "subscription_expires_at": future}
expired = {"subscription_status": "active", "subscription_expires_at": past}
assert catalog_access_status(None, None, now=now) == 401
assert catalog_access_status("invalid", None, now=now) == 401
assert catalog_access_status("token", {}, now=now) == 403
assert catalog_access_status("token", expired, now=now) == 403
assert catalog_access_status("token", {"subscription_status": "pending", "subscription_expires_at": future}, now=now) == 403
assert catalog_access_status("token", active, now=now) == 200
assert catalog_access_status("token", trial, now=now) == 200
print("PASS: signed channel catalog requires an active POTV session")
