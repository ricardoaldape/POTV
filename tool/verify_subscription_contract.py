#!/usr/bin/env python3
"""Fail closed if any POTV update drops the mandatory customer subscription gate.

This fast offline check must run before every QA/release/OTA build.
The server tests validate actual subscription math and manual approvals.
"""
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent


def require(relative, *fragments):
    path = ROOT / relative
    if not path.is_file():
        raise SystemExit(f"SUBSCRIPTION GATE MISSING: {relative}")
    content = path.read_text(encoding="utf-8")
    for fragment in fragments:
        if fragment not in content:
            raise SystemExit(f"SUBSCRIPTION CONTRACT BROKEN: {relative} lacks {fragment!r}")


def main():
    require("lib/app/potv_app.dart", "account.hasViewingAccess",
            "SubscriptionLockedScreen", "refreshSubscription")
    require("lib/data/accounts/user_account.dart",
            "SubscriptionStatus.trial", "renewalWarning", "hasViewingAccess")
    require("lib/features/home/home_screen.dart", "renewalWarning", "remainingDays")
    require("lib/ui/subscription/subscription_locked_screen.dart",
            "comprobar activación", "Solicitar activación")
    require("backend/potv-bot/account_store.py",
            "TRIAL_DURATION", "activate_manual", "subscription_billing_day",
            "app_manual_activations")
    require("backend/potv-bot/subscription_policy.py",
            "timedelta(days=5)", "monthly_expiry", "RENEWAL_NOTICE")
    require("backend/potv-bot/content_access.py",
            '"active", "trial"', "subscription_expires_at")
    require("backend/potv-bot/test_subscriptions.py", "test_end_of_month",
            "test_trial_five_days", "test_notice_at_ten_days")
    require("backend/potv-bot/activate_account.py", "payment_confirmed")
    require("backend/potv-bot/grant_permanent.py", "app_complimentary_grants", "PERMANENT_EXPIRY", "approved_by")
    require("test/subscription_access_test.dart",
            "trial grants access", "expired accounts cannot watch")
    env = __import__("os").environ.copy()
    env["PYTHONDONTWRITEBYTECODE"] = "1"
    subprocess.run(
        [sys.executable, "-m", "unittest", "-q", "test_subscriptions", "test_grant_permanent"],
        check=True, cwd=ROOT / "backend" / "potv-bot", env=env,
    )
    print("PASS POTV SUBSCRIPTION CONTRACT: five-day trial, monthly billing,"
          " manual authorization, expiry gate and ten-day banner")


if __name__ == "__main__":
    main()
