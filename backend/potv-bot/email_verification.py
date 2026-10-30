"""POTV email-ownership challenge before any five-day trial starts.

Only SHA256(salt + OTP) and PBKDF2 password hashes are stored in SQLite.
SMTP transport must be configured before registration can be enabled.
"""
import hashlib
import os
import re
import secrets
import smtplib
import sqlite3
import ssl
import uuid
from datetime import timedelta
from email.message import EmailMessage

from account_store import _EMAIL_RE, _hash_password, _iso, _now, AccountError
from subscription_policy import TRIAL_DURATION

CODE_TTL = timedelta(minutes=15)
RESEND_COOLDOWN = timedelta(seconds=60)
MAX_ATTEMPTS = 5


def smtp_ready():
    return all(os.getenv(key, '').strip() for key in (
        'POTV_SMTP_HOST', 'POTV_SMTP_USER', 'POTV_SMTP_PASSWORD',
        'POTV_SMTP_FROM'))


def send_verification(to_email, code):
    if not smtp_ready():
        raise AccountError('verification_unavailable')
    host = os.environ['POTV_SMTP_HOST'].strip()
    port = int(os.getenv('POTV_SMTP_PORT', '587'))
    if port not in (465, 587):
        raise AccountError('verification_unavailable')
    msg = EmailMessage()
    msg['From'] = os.environ['POTV_SMTP_FROM']
    msg['To'] = to_email
    msg['Subject'] = 'Confirma tu correo para activar POTV'
    msg.set_content(
        'Tu codigo de verificacion POTV es: ' + code + '\n'
        'Es valido durante 15 minutos. No lo compartas con nadie.\n'
        'Los 5 dias gratis empiezan solo despues de verificar tu correo.\n'
        'Si no solicitaste una cuenta POTV, ignora este mensaje.\n'
    )
    ctx = ssl.create_default_context()
    try:
        if port == 465:
            smtp = smtplib.SMTP_SSL(host, port, timeout=12, context=ctx)
        else:
            smtp = smtplib.SMTP(host, port, timeout=12)
        with smtp:
            if port == 587:
                smtp.starttls(context=ctx)
            smtp.login(os.environ['POTV_SMTP_USER'], os.environ['POTV_SMTP_PASSWORD'])
            smtp.send_message(msg)
    except (OSError, smtplib.SMTPException) as exc:
        raise AccountError('verification_delivery_failed') from exc


class PendingRegistrations:
    def __init__(self, db_path, send=send_verification):
        self.db_path = db_path
        self.send = send

    def _db(self):
        con = sqlite3.connect(self.db_path, timeout=20)
        con.row_factory = sqlite3.Row
        return con

    def init(self):
        with self._db() as db:
            db.execute("""CREATE TABLE IF NOT EXISTS app_pending_email_registrations (
                email TEXT PRIMARY KEY COLLATE NOCASE, username TEXT NOT NULL,
                password_salt TEXT NOT NULL, password_hash TEXT NOT NULL,
                code_salt TEXT NOT NULL, code_hash TEXT NOT NULL,
                created_at TEXT NOT NULL, expires_at TEXT NOT NULL,
                resend_after TEXT NOT NULL, attempts INTEGER NOT NULL DEFAULT 0
            )""")

    @staticmethod
    def _validate(email, password, name):
        email = (email or '').strip().lower()
        name = (name or '').strip()
        if not _EMAIL_RE.match(email) or len(email) > 254:
            raise AccountError('invalid_email')
        if not isinstance(password, str) or not 8 <= len(password) <= 128:
            raise AccountError('invalid_password')
        if not 2 <= len(name) <= 48:
            raise AccountError('invalid_name')
        return email, name

    def _issue(self, email, name=None, password=None, resend=False):
        if not smtp_ready():
            raise AccountError('verification_unavailable')
        now = _now()
        code = f'{secrets.randbelow(1000000):06d}'
        salt = secrets.token_hex(16)
        digest = hashlib.sha256((salt + code).encode()).hexdigest()
        with self._db() as db:
            db.execute('BEGIN IMMEDIATE')
            exists = db.execute('SELECT id FROM app_accounts WHERE email=?', (email,)).fetchone()
            if exists:
                raise AccountError('account_exists')
            previous = db.execute('SELECT * FROM app_pending_email_registrations WHERE email=?', (email,)).fetchone()
            if previous and _iso(now) < previous['resend_after']:
                raise AccountError('verification_rate_limited')
            if resend:
                if not previous or previous['expires_at'] <= _iso(now):
                    raise AccountError('verification_expired')
                name = previous['username']
                pass_salt, pass_hash = previous['password_salt'], previous['password_hash']
            else:
                pass_salt = secrets.token_hex(16)
                pass_hash = _hash_password(password, bytes.fromhex(pass_salt))
            db.execute("""INSERT INTO app_pending_email_registrations (
                email,username,password_salt,password_hash,code_salt,code_hash,
                created_at,expires_at,resend_after,attempts)
                VALUES (?,?,?,?,?,?,?,?,?,0)
                ON CONFLICT(email) DO UPDATE SET
                username=excluded.username,password_salt=excluded.password_salt,
                password_hash=excluded.password_hash,code_salt=excluded.code_salt,
                code_hash=excluded.code_hash,created_at=excluded.created_at,
                expires_at=excluded.expires_at,resend_after=excluded.resend_after,
                attempts=0""", (
                email,name,pass_salt,pass_hash,salt,digest,_iso(now),
                _iso(now+CODE_TTL),_iso(now+RESEND_COOLDOWN)))
        try:
            self.send(email, code)
        except Exception:
            # A failed email cannot create a free trial. Allow safe retries.
            with self._db() as db:
                db.execute('DELETE FROM app_pending_email_registrations WHERE email=? AND code_hash=?', (email,digest))
            raise AccountError('verification_delivery_failed')
        return {'ok': True, 'verification_required': True, 'email': email}

    def begin(self, email, password, name):
        email, name = self._validate(email, password, name)
        return self._issue(email, name=name, password=password)

    def resend(self, email):
        email = (email or '').strip().lower()
        if not _EMAIL_RE.match(email) or len(email) > 254:
            raise AccountError('invalid_email')
        return self._issue(email, resend=True)

    def verify(self, email, code):
        email = (email or '').strip().lower()
        code = (code or '').strip()
        if not _EMAIL_RE.match(email) or not re.fullmatch(r'\d{6}', code):
            raise AccountError('invalid_verification_code')
        now = _now()
        with self._db() as db:
            db.execute('BEGIN IMMEDIATE')
            row = db.execute('SELECT * FROM app_pending_email_registrations WHERE email=?', (email,)).fetchone()
            if row is None or row['expires_at'] <= _iso(now):
                raise AccountError('verification_expired')
            if row['attempts'] >= MAX_ATTEMPTS:
                raise AccountError('verification_attempts_exceeded')
            expected = hashlib.sha256((row['code_salt'] + code).encode()).hexdigest()
            if not secrets.compare_digest(expected, row['code_hash']):
                db.execute('UPDATE app_pending_email_registrations SET attempts=attempts+1 WHERE email=?', (email,))
                # Commit attempt count before raising: connection context rolls back on exception.
                db.commit()
                raise AccountError('invalid_verification_code')
            created = _iso(now)
            try:
                db.execute("""INSERT INTO app_accounts (
                    id,email,username,password_salt,password_hash,
                    subscription_status,subscription_expires_at,created_at,updated_at)
                    VALUES (?,?,?,?,?,?,?,?,?)""", (
                    str(uuid.uuid4()),email,row['username'],row['password_salt'],
                    row['password_hash'],'trial',_iso(now+TRIAL_DURATION),created,created))
            except sqlite3.IntegrityError as exc:
                raise AccountError('account_exists') from exc
            db.execute('DELETE FROM app_pending_email_registrations WHERE email=?', (email,))
        return {'ok': True, 'verified': True}
