import os
import sqlite3
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from account_store import AccountStore, AccountError
from subscription_policy import monthly_expiry, subscription_state


def utc(s):
    return datetime.fromisoformat(s).astimezone(timezone.utc)


class SubscriptionTests(unittest.TestCase):
    def setUp(self):
        handle, self.path = tempfile.mkstemp(prefix="potv-billing-", suffix=".db")
        os.close(handle)
        self.store = AccountStore(self.path)
        self.store.init()
        self.new = self.store.register("Trial@Example.com", "Good-Password-123", "Prueba")

    def tearDown(self):
        for suffix in ("", "-shm", "-wal"):
            try:
                os.remove(self.path + suffix)
            except FileNotFoundError:
                pass

    def test_trial_five_days_and_cannot_register_twice(self):
        self.assertEqual(self.new["subscription_status"], "trial")
        self.assertTrue(self.new["access_allowed"])
        created = utc(self.new["created_at"])
        end = utc(self.new["subscription_expires_at"])
        self.assertEqual(end - created, timedelta(days=5))
        self.assertTrue(subscription_state("trial", end, end-timedelta(seconds=1))["access_allowed"])
        self.assertFalse(subscription_state("trial", end, end)["access_allowed"])
        with self.assertRaises(AccountError) as caught:
            self.store.register("trial@example.com", "Good-Password-123", "Otra")
        self.assertEqual(caught.exception.code, "account_exists")

    def test_monthly_same_date_and_time(self):
        start = utc("2026-10-15T20:30:00+00:00")
        next_month = monthly_expiry(start)
        self.assertEqual(next_month.astimezone(
            __import__("zoneinfo").ZoneInfo("America/Mexico_City")
        ).isoformat(), "2026-11-15T14:30:00-06:00")

    def test_end_of_month_non_leap_and_leap(self):
        jan31 = utc("2027-01-31T16:00:00+00:00")
        feb28 = monthly_expiry(jan31, billing_day=31)
        self.assertEqual(feb28.date().isoformat(), "2027-02-28")
        mar31 = monthly_expiry(feb28, billing_day=31)
        self.assertEqual(mar31.date().isoformat(), "2027-03-31")
        leap = monthly_expiry(utc("2028-01-31T16:00:00+00:00"), billing_day=31)
        self.assertEqual(leap.date().isoformat(), "2028-02-29")

    def test_approval_and_early_renewal_keep_billing_day(self):
        jan31 = utc("2027-01-31T16:00:00+00:00")
        acct = self.store.activate_manual(
            "trial@example.com", approved_by="owner", payment_confirmed=True,
            payment_reference="test-receipt-001", at=jan31)
        self.assertEqual(acct["subscription_status"], "active")
        self.assertEqual(utc(acct["subscription_expires_at"]).date().isoformat(), "2027-02-28")
        updated = self.store.activate_manual(
            "trial@example.com", approved_by="owner", payment_confirmed=True,
            payment_reference="test-receipt-002", at=jan31+timedelta(days=1))
        self.assertEqual(utc(updated["subscription_expires_at"]).date().isoformat(), "2027-03-31")

    def test_notice_at_ten_days_only_paid(self):
        now = utc("2026-10-15T20:30:00+00:00")
        expiry = now + timedelta(days=10)
        self.assertTrue(subscription_state("active", expiry, now)["renewal_notice"])
        self.assertFalse(subscription_state("trial", expiry, now)["renewal_notice"])
        self.assertFalse(subscription_state("active", expiry + timedelta(seconds=1), now)["renewal_notice"])
        self.assertFalse(subscription_state("active", now, now)["access_allowed"])

    def test_requires_approval_and_blocks_duplicate_receipt(self):
        with self.assertRaises(AccountError):
            self.store.activate_manual("trial@example.com", approved_by="owner")
        self.store.activate_manual(
            "trial@example.com", approved_by="owner", payment_confirmed=True,
            payment_reference="receipt-dup-01")
        with self.assertRaises(AccountError) as caught:
            self.store.activate_manual(
                "trial@example.com", approved_by="owner", payment_confirmed=True,
                payment_reference="receipt-dup-01")
        self.assertEqual(caught.exception.code, "duplicate_payment_reference")
        with sqlite3.connect(self.path) as db:
            self.assertEqual(db.execute("SELECT COUNT(*) FROM app_manual_activations").fetchone()[0], 1)

    def test_existing_active_account_migration(self):
        old = self.store.register("old@example.com", "Good-Password-123", "Old")
        with self.store._db() as c:
            c.execute("""UPDATE app_accounts SET subscription_status='active',
                subscription_expires_at='2028-03-15T14:00:00+00:00' WHERE id=?""", (old["id"],))
        self.store.init()
        restored = self.store.account_by_email("old@example.com")
        self.assertTrue(restored["access_allowed"])
        self.assertEqual(restored["subscription_status"], "active")


if __name__ == "__main__":
    unittest.main()