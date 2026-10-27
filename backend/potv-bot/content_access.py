"""First-party POTV subscription checks for access to licensed VOD.

POTV customers authenticate with POTV sessions; upstream provider accounts
never appear in the Android APK or user-facing API. This module deliberately
does not grant access to any third-party content on its own.
"""
from datetime import datetime, timezone


def has_active_subscription(account, *, now=None):
    if not isinstance(account, dict):
        return False
    if str(account.get("subscription_status") or "").lower() not in {"active", "trial"}:
        return False
    expiry = account.get("subscription_expires_at")
    if not isinstance(expiry, str) or not expiry.strip():
        return False
    try:
        end = datetime.fromisoformat(expiry.strip().replace("Z", "+00:00"))
        if end.tzinfo is None or end.utcoffset() is None:
            return False
        current = now or datetime.now(timezone.utc)
        if current.tzinfo is None or current.utcoffset() is None:
            return False
        return end.astimezone(timezone.utc) > current.astimezone(timezone.utc)
    except (ValueError, TypeError, OverflowError):
        return False


def requires_vod_subscription(gateway, environment):
    """Fail closed for enabled LMHD paid VOD, optional for other providers.

    Public-domain and existing freely licensed VOD aren't accidentally
    restricted until POTV explicitly enables that flag in production.
    """
    if getattr(gateway, "lmhd_vod_enabled", False):
        return True
    if getattr(gateway, "nova_vod_enabled", False):
        return True
    return str(environment.get("POTV_REQUIRE_VOD_SUBSCRIPTION") or "").strip().lower() in {
        "true", "1", "yes"
    }