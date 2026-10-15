#!/usr/bin/env python3
"""Manual POTV account activation. SSH/admin-only, never public HTTP.

Usage:
python3 activate_account.py status cliente@ejemplo.com
python3 activate_account.py activate cliente@ejemplo.com --payment-confirmed \
    --reference folio-123 --paid-at 2026-10-15T14:30:00-06:00
"""
import argparse
import json
import os
import sys
from account_store import AccountStore, AccountError

BASE = os.path.dirname(os.path.abspath(__file__))
DB = os.environ.get("POTV_DB") or os.path.join(BASE, "potv.sqlite3")


def main():
    parser = argparse.ArgumentParser(description="POTV: activación manual por correo")
    sub = parser.add_subparsers(dest="command", required=True)
    status = sub.add_parser("status")
    status.add_argument("email")
    activate = sub.add_parser("activate")
    activate.add_argument("email")
    activate.add_argument("--payment-confirmed", action="store_true", required=True)
    activate.add_argument("--reference", default=None)
    activate.add_argument("--paid-at", default=None)
    activate.add_argument("--approved-by", default="owner-chat-approval")
    args = parser.parse_args()

    if args.command == "activate" and not args.payment_confirmed:
        parser.error("Se requiere aprobación humana del pago.")
    store = AccountStore(DB)
    store.init()
    try:
        result = (store.account_by_email(args.email) if args.command == "status"
                  else store.activate_manual(
                      args.email, approved_by=args.approved_by,
                      payment_confirmed=args.payment_confirmed,
                      payment_reference=args.reference,
                      payment_paid_at=args.paid_at))
        if result is None:
            raise AccountError("account_not_found")
        print(json.dumps({
            "email": result["email"],
            "status": result["subscription_status"],
            "expires_at": result["subscription_expires_at"],
            "access_allowed": result["access_allowed"],
            "renewal_notice": result["renewal_notice"],
            "days_remaining": result["days_remaining"],
        }, ensure_ascii=False, indent=2))
    except AccountError as exc:
        print(json.dumps({"ok": False, "error": exc.code}), file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())