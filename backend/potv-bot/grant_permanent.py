#!/usr/bin/env python3
"""Administratively grant unlimited POTV testing access to an EXISTING account.

No fabricated payment or public HTTP endpoint. Existing Flutter clients remain
compatible: active + a distant sentinel expiry; a separate audit table marks
this as a complimentary permanent grant.
"""
import argparse
import json
import os
import re
import sqlite3
from datetime import datetime, timezone
from pathlib import Path

PERMANENT_EXPIRY = "9999-12-31T23:59:59+00:00"


def grant_permanent(db_path, email, *, approved_by, reason):
    normalized = str(email or "").strip().lower()
    if not re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", normalized):
        raise ValueError("invalid_email")
    if not approved_by or not reason:
        raise ValueError("explicit_operator_and_reason_required")
    connection = sqlite3.connect(str(db_path), timeout=20)
    try:
        connection.execute("BEGIN IMMEDIATE")
        connection.execute("""
            CREATE TABLE IF NOT EXISTS app_complimentary_grants (
                account_id TEXT PRIMARY KEY,
                granted_at TEXT NOT NULL,
                granted_by TEXT NOT NULL,
                reason TEXT NOT NULL,
                original_status TEXT NOT NULL,
                original_expires_at TEXT,
                FOREIGN KEY(account_id) REFERENCES app_accounts(id)
            )
        """)
        row = connection.execute(
            "SELECT id,subscription_status,subscription_expires_at FROM app_accounts WHERE email=? COLLATE NOCASE",
            (normalized,),
        ).fetchone()
        if row is None:
            raise ValueError("account_not_found")
        account_id, previous_status, previous_expiry = row
        stamp = datetime.now(timezone.utc).isoformat()
        existing = connection.execute(
            "SELECT 1 FROM app_complimentary_grants WHERE account_id=?",
            (account_id,),
        ).fetchone()
        if not existing:
            connection.execute("""
                INSERT INTO app_complimentary_grants
                (account_id,granted_at,granted_by,reason,original_status,original_expires_at)
                VALUES (?,?,?,?,?,?)
            """, (account_id, stamp, approved_by, reason, previous_status, previous_expiry))
        connection.execute("""
            UPDATE app_accounts
               SET subscription_status='active',
                   subscription_expires_at=?,
                   updated_at=?
             WHERE id=?
        """, (PERMANENT_EXPIRY, stamp, account_id))
        connection.commit()
        current = connection.execute(
            "SELECT subscription_status,subscription_expires_at FROM app_accounts WHERE id=?",
            (account_id,),
        ).fetchone()
        return {
            "email": normalized,
            "complimentary_permanent": True,
            "already_granted": bool(existing),
            "subscription_status": current[0],
            "subscription_expires_at": current[1],
        }
    except Exception:
        connection.rollback()
        raise
    finally:
        connection.close()


def main():
    parser = argparse.ArgumentParser(description="Authorize permanent courtesy access for an existing POTV account.")
    parser.add_argument("email")
    parser.add_argument("--approved-by", required=True)
    parser.add_argument("--reason", required=True)
    parser.add_argument("--db", default=str(Path(__file__).with_name("potv.sqlite3")))
    args = parser.parse_args()
    data = grant_permanent(args.db, args.email, approved_by=args.approved_by, reason=args.reason)
    print(json.dumps(data, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()