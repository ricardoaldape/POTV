#!/usr/bin/env python3
"""Synchronize the permitted LMHD TV/EPG/events snapshot privately for POTV.

Never embeds provider passwords or access tokens in the client catalog. A
separate signed proxy still protects playback and checks POTV subscriptions.
The sync runs under systemd even when no subscribers are online.
"""
import json
import os
import tempfile
from datetime import datetime, timezone
from pathlib import Path

from lmhd_partner import LmhdPartner, LmhdLoginPartner, PartnerApiError
from partner_lmhd_api import PartnerAccessError

MAX_SNAPSHOT_BYTES = 8 * 1024 * 1024


def write_snapshot(path, partner):
    channels = partner.tv_channels()
    events = partner.sports_events()
    if not isinstance(channels, list) or not isinstance(events, list):
        raise ValueError("lmhd_invalid_catalog")
    # The parser validates explicit playable media and filters locked or
    # invalid rows; zero rows are valid only if the provider returned them.
    payload = {
        "version": 1,
        "updated_at": datetime.now(timezone.utc).isoformat(),
        "channels": channels[:6000],
        "sports_events": events[:1500],
    }
    body = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    if len(body) > MAX_SNAPSHOT_BYTES:
        raise ValueError("lmhd_snapshot_too_large")
    target = Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    temp_name = ""
    try:
        with tempfile.NamedTemporaryFile(mode="wb", dir=target.parent,
                                         prefix=".lmhd-", delete=False) as out:
            temp_name = out.name
            os.chmod(temp_name, 0o600)
            out.write(body)
            out.flush()
            os.fsync(out.fileno())
        os.replace(temp_name, target)
        os.chmod(target, 0o600)
    finally:
        if temp_name and os.path.exists(temp_name):
            os.unlink(temp_name)
    return len(payload["channels"]), len(payload["sports_events"])


def run():
    service_file = os.getenv("POTV_LMHD_SERVICE_FILE", "").strip()
    output = os.getenv("POTV_LMHD_SYNC_FILE", "").strip()
    if not output:
        print("LMHD_SYNC_NOT_CONFIGURED")
        return 0
    try:
        if service_file:
            if not Path(service_file).is_file():
                print("LMHD_SYNC_NOT_CONFIGURED")
                return 0
            partner = LmhdPartner.from_file(service_file)
        else:
            # The already-supported LMHD service-account login uses private
            # POTV_LMHD_* environment variables, rotating sessions itself.
            partner = LmhdLoginPartner.from_environment()
        if partner is None:
            print("LMHD_SYNC_DISABLED")
            return 0
        channels, events = write_snapshot(output, partner)
        print("LMHD_SYNC_OK channels=%d events=%d" % (channels, events))
        return 0
    except PartnerApiError as exc:
        if exc.code in ("partner_session_denied", "partner_authorization_or_api_error"):
            # Never continue serving stale links after a revoked session.
            Path(output).unlink(missing_ok=True)
        print("LMHD_SYNC_FAILED code=%s" % exc.code)
        return 1
    except (OSError, ValueError, TypeError, KeyError, PartnerAccessError):
        print("LMHD_SYNC_FAILED code=provider_snapshot_unavailable")
        return 1


if __name__ == "__main__":
    raise SystemExit(run())
