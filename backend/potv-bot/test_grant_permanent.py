"""Courtesy grants never forge payments and never depend on monthly renewals."""
import gc
import os
import tempfile
import unittest

from account_store import AccountStore
from content_access import has_active_subscription
from grant_permanent import PERMANENT_EXPIRY, grant_permanent


class ComplimentaryGrantTests(unittest.TestCase):
    def setUp(self):
        handle, self.path = tempfile.mkstemp(prefix="potv-comp-", suffix=".db")
        os.close(handle)
        self.store = AccountStore(self.path)
        self.store.init()
        self.store.register("owner@example.com", "StrongPass123!", "Owner")

    def tearDown(self):
        self.store = None
        gc.collect()
        for suffix in ("", "-wal", "-shm"):
            try:
                os.remove(self.path + suffix)
            except FileNotFoundError:
                pass

    def test_permanent_grant_no_renewal_and_idempotent(self):
        a = grant_permanent(
            self.path, "OWNER@example.com", approved_by="operator",
            reason="explicit owner test account"
        )
        self.assertTrue(a["complimentary_permanent"])
        self.assertFalse(a["already_granted"])
        self.assertEqual(a["subscription_expires_at"], PERMANENT_EXPIRY)
        user = self.store.account_by_email("owner@example.com")
        self.assertTrue(user["access_allowed"])
        self.assertTrue(has_active_subscription(user))
        self.assertFalse(user["renewal_notice"])
        again = grant_permanent(
            self.path, "owner@example.com", approved_by="operator",
            reason="explicit owner test account"
        )
        self.assertTrue(again["already_granted"])

    def test_denies_nonexistent_account_or_missing_approval(self):
        with self.assertRaises(ValueError):
            grant_permanent(self.path, "other@example.com",
                            approved_by="operator", reason="test")
        with self.assertRaises(ValueError):
            grant_permanent(self.path, "owner@example.com",
                            approved_by="", reason="test")


if __name__ == "__main__":
    unittest.main()
