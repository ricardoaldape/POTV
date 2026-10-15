"""POTV subscription rules. Server time is authoritative.

Trials last exactly five 24-hour days; paid months follow calendar dates in
America/Mexico_City. On day 29/30/31 where missing, clamp to month's last day
without losing the original subscription billing day on subsequent renewals.
"""
import calendar
import math
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

LOCAL_TZ = ZoneInfo("America/Mexico_City")
TRIAL_DURATION = timedelta(days=5)
RENEWAL_NOTICE = timedelta(days=10)


def aware(value):
    if isinstance(value, datetime):
        date = value
    elif isinstance(value, str) and value.strip():
        date = datetime.fromisoformat(value.strip().replace("Z", "+00:00"))
    else:
        return None
    if date.tzinfo is None or date.utcoffset() is None:
        return None
    return date.astimezone(timezone.utc)


def monthly_expiry(start, billing_day=None):
    """Move forward one Mexican calendar month retaining local clock and day."""
    instant = aware(start)
    if instant is None:
        raise ValueError("invalid_start")
    local = instant.astimezone(LOCAL_TZ)
    billing_day = billing_day or local.day
    if not isinstance(billing_day, int) or billing_day < 1 or billing_day > 31:
        raise ValueError("invalid_billing_day")
    year = local.year + (local.month // 12)
    month = local.month % 12 + 1
    day = min(billing_day, calendar.monthrange(year, month)[1])
    return local.replace(year=year, month=month, day=day).astimezone(timezone.utc)


def subscription_state(status, expires_at, at=None):
    stamp = aware(at) or datetime.now(timezone.utc)
    expiry = aware(expires_at)
    kind = str(status or "free").strip().lower()
    valid = kind in ("trial", "active") and expiry is not None and expiry > stamp
    status_out = kind if valid else (
        "expired" if kind in ("trial", "active", "expired") else kind
    )
    seconds = max(0.0, (expiry - stamp).total_seconds()) if expiry else 0.0
    return {
        "subscription_status": status_out,
        "subscription_expires_at": expiry.isoformat() if expiry else None,
        "access_allowed": valid,
        "days_remaining": math.ceil(seconds / 86400) if valid else 0,
        "renewal_notice": (
            kind == "active" and valid and
            expiry - stamp <= RENEWAL_NOTICE
        ),
        "server_now": stamp.isoformat(),
    }