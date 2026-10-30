"""Offline OTP tests: never call SMTP, Telegram or production DB."""
import os
import sqlite3
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from unittest.mock import patch
from account_store import AccountStore, AccountError
from email_verification import PendingRegistrations


class EmailVerificationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.path = os.path.join(self.temp.name, 'accounts.sqlite')
        self.store = AccountStore(self.path)
        self.store.init()
        self.sent = []
        self.verifier = PendingRegistrations(self.path, send=lambda email, code: self.sent.append((email, code)))
        self.verifier.init()
        self.config = patch.dict(os.environ, {
            'POTV_SMTP_HOST': 'mail.test.invalid', 'POTV_SMTP_FROM': 'POTV <noreply@test.invalid>',
            'POTV_SMTP_USER': 'test', 'POTV_SMTP_PASSWORD': 'test',
        })
        self.config.start()

    def tearDown(self):
        self.config.stop()
        self.temp.cleanup()

    def start(self, email='first@example.com'):
        return self.verifier.begin(email, 'A-strong-password-123', 'First user')

    def test_five_days_start_only_after_verified_email(self):
        before = datetime.now(timezone.utc)
        response = self.start()
        self.assertTrue(response['verification_required'])
        self.assertIsNone(self.store.account_by_email('first@example.com'))
        self.assertEqual(len(self.sent), 1)
        confirmed = self.verifier.verify('first@example.com', self.sent[0][1])
        self.assertTrue(confirmed['verified'])
        account = self.store.account_by_email('first@example.com')
        self.assertEqual(account['subscription_status'], 'trial')
        created = datetime.fromisoformat(account['created_at'])
        expires = datetime.fromisoformat(account['subscription_expires_at'])
        self.assertGreaterEqual(created, before)
        self.assertEqual(expires-created, timedelta(days=5))
        self.assertTrue(self.store.login('first@example.com','A-strong-password-123')['access_token'])

    def test_wrong_code_replay_and_attempt_limit(self):
        self.start()
        with self.assertRaises(AccountError) as err:
            self.verifier.verify('first@example.com', '999999' if self.sent[0][1] != '999999' else '888888')
        self.assertEqual(err.exception.code, 'invalid_verification_code')
        self.assertIsNone(self.store.account_by_email('first@example.com'))
        self.assertEqual(self.verifier.verify('first@example.com', self.sent[0][1])['verified'], True)
        with self.assertRaises(AccountError):
            self.verifier.verify('first@example.com', self.sent[0][1])
        self.start('second@example.com')
        code = '999999' if self.sent[-1][1] != '999999' else '888888'
        for _ in range(5):
            with self.assertRaises(AccountError): self.verifier.verify('second@example.com', code)
        with self.assertRaises(AccountError) as err:
            self.verifier.verify('second@example.com', self.sent[-1][1])
        self.assertEqual(err.exception.code, 'verification_attempts_exceeded')

    def test_rate_limit_delivery_failure_existing_account(self):
        self.start()
        with self.assertRaises(AccountError) as err:
            self.start()
        self.assertEqual(err.exception.code, 'verification_rate_limited')
        self.verifier.verify('first@example.com', self.sent[0][1])
        with self.assertRaises(AccountError) as err:
            self.start()
        self.assertEqual(err.exception.code, 'account_exists')
        failure = PendingRegistrations(self.path, send=lambda *_: (_ for _ in ()).throw(OSError('smtp down')))
        with self.assertRaises(AccountError) as err:
            failure.begin('fail@example.com','A-strong-password-123','User')
        self.assertEqual(err.exception.code,'verification_delivery_failed')
        self.assertIsNone(self.store.account_by_email('fail@example.com'))
        with sqlite3.connect(self.path) as db:
            self.assertIsNone(db.execute('SELECT 1 FROM app_pending_email_registrations WHERE email=?',('fail@example.com',)).fetchone())

    def test_expired_code_and_resend_cooldown(self):
        self.start()
        with self.assertRaises(AccountError) as err:
            self.verifier.resend('first@example.com')
        self.assertEqual(err.exception.code,'verification_rate_limited')
        with sqlite3.connect(self.path) as db:
            db.execute("UPDATE app_pending_email_registrations SET resend_after='2000-01-01T00:00:00+00:00'")
        self.verifier.resend('first@example.com')
        self.assertEqual(len(self.sent),2)
        with sqlite3.connect(self.path) as db:
            db.execute("UPDATE app_pending_email_registrations SET expires_at='2000-01-01T00:00:00+00:00'")
        with self.assertRaises(AccountError) as err:
            self.verifier.verify('first@example.com',self.sent[-1][1])
        self.assertEqual(err.exception.code,'verification_expired')

    def test_smtp_missing_fails_closed(self):
        with patch.dict(os.environ, {'POTV_SMTP_PASSWORD': ''}):
            with self.assertRaises(AccountError) as err:
                self.start()
        self.assertEqual(err.exception.code,'verification_unavailable')
        self.assertIsNone(self.store.account_by_email('first@example.com'))

if __name__=='__main__': unittest.main()
