import hashlib
import hmac
import re
import secrets
import sqlite3
import string
import uuid
from datetime import datetime, timedelta, timezone
from subscription_policy import LOCAL_TZ, TRIAL_DURATION, aware, monthly_expiry, subscription_state

_EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
_PBKDF2_ITERATIONS = 260_000
_SESSION_DAYS = 30
_RECOVERY_MINUTES = 15

class AccountError(Exception):
    def __init__(self, code):
        super().__init__(code)
        self.code = code

def _now():
    return datetime.now(timezone.utc)

def _iso(value):
    return value.astimezone(timezone.utc).isoformat()

def _parse(value):
    return datetime.fromisoformat(value) if value else None

def _hash_password(password, salt):
    return hashlib.pbkdf2_hmac(
        "sha256", password.encode("utf-8"), salt, _PBKDF2_ITERATIONS
    ).hex()

def _token_hash(token):
    return hashlib.sha256(token.encode("utf-8")).hexdigest()

class AccountStore:
    def __init__(self, db_path):
        self.db_path = db_path

    def _db(self):
        con = sqlite3.connect(self.db_path, timeout=20)
        con.row_factory = sqlite3.Row
        return con

    def init(self):
        with self._db() as con:
            con.executescript("""
            CREATE TABLE IF NOT EXISTS app_accounts(
              id TEXT PRIMARY KEY,
              email TEXT NOT NULL UNIQUE COLLATE NOCASE,
              username TEXT NOT NULL,
              password_salt TEXT NOT NULL,
              password_hash TEXT NOT NULL,
              telegram_id INTEGER UNIQUE,
              subscription_status TEXT NOT NULL DEFAULT 'free',
              subscription_expires_at TEXT,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS app_sessions(
              token_hash TEXT PRIMARY KEY,
              account_id TEXT NOT NULL,
              expires_at TEXT NOT NULL,
              created_at TEXT NOT NULL,
              FOREIGN KEY(account_id) REFERENCES app_accounts(id)
            );
            CREATE INDEX IF NOT EXISTS idx_app_sessions_account
              ON app_sessions(account_id);
            CREATE TABLE IF NOT EXISTS app_recovery_codes(
              code_hash TEXT PRIMARY KEY,
              account_id TEXT NOT NULL,
              expires_at TEXT NOT NULL,
              used_at TEXT,
              created_at TEXT NOT NULL,
              FOREIGN KEY(account_id) REFERENCES app_accounts(id)
            );
            CREATE INDEX IF NOT EXISTS idx_app_recovery_account
              ON app_recovery_codes(account_id);
            """)
            cols = {row[1] for row in con.execute("PRAGMA table_info(app_accounts)")}
            if "subscription_billing_day" not in cols:
                con.execute("ALTER TABLE app_accounts ADD COLUMN subscription_billing_day INTEGER")
            con.execute("""
                CREATE TABLE IF NOT EXISTS app_manual_activations (
                  id INTEGER PRIMARY KEY AUTOINCREMENT,
                  account_id TEXT NOT NULL,
                  payment_reference TEXT,
                  payment_paid_at TEXT,
                  approved_by TEXT NOT NULL,
                  approved_at TEXT NOT NULL,
                  starts_at TEXT NOT NULL,
                  previous_expires_at TEXT,
                  new_expires_at TEXT NOT NULL,
                  FOREIGN KEY(account_id) REFERENCES app_accounts(id)
                )
            """)
            con.execute("""
                CREATE UNIQUE INDEX IF NOT EXISTS idx_manual_payment_reference
                ON app_manual_activations(payment_reference)
                WHERE payment_reference IS NOT NULL
            """)

    def _payload(self, row):
        if row is None:
            return None
        return {
            "id": row["id"],
            "email": row["email"],
            "username": row["username"],
            "created_at": row["created_at"],
            "telegram_chat_id": None if row["telegram_id"] is None else str(row["telegram_id"]),
            **subscription_state(
                row["subscription_status"], row["subscription_expires_at"]
            ),
        }

    def register(self, email, password, username):
        email = (email or "").strip().lower()
        username = (username or "").strip()
        if not _EMAIL_RE.match(email) or len(email) > 254:
            raise AccountError("invalid_email")
        if len(password or "") < 8 or len(password) > 128:
            raise AccountError("invalid_password")
        if len(username) < 2 or len(username) > 48:
            raise AccountError("invalid_name")
        salt = secrets.token_bytes(16)
        account_id = str(uuid.uuid4())
        stamp = _iso(_now())
        trial_end = _iso(aware(stamp) + TRIAL_DURATION)
        try:
            with self._db() as con:
                con.execute(
                    """INSERT INTO app_accounts
                    (id,email,username,password_salt,password_hash,
                     subscription_status,subscription_expires_at,
                     created_at,updated_at)
                    VALUES(?,?,?,?,?,?,?,?,?)""",
                    (
                        account_id,
                        email,
                        username,
                        salt.hex(),
                        _hash_password(password, salt),
                        "trial",
                        trial_end,
                        stamp,
                        stamp,
                    ),
                )
                row = con.execute(
                    "SELECT * FROM app_accounts WHERE id=?", (account_id,)
                ).fetchone()
        except sqlite3.IntegrityError as exc:
            raise AccountError("account_exists") from exc
        return self._payload(row)

    def login(self, email, password):
        email = (email or "").strip().lower()
        with self._db() as con:
            row = con.execute(
                "SELECT * FROM app_accounts WHERE email=?", (email,)
            ).fetchone()
            if row is None:
                raise AccountError("invalid_credentials")
            try:
                salt = bytes.fromhex(row["password_salt"])
            except ValueError as exc:
                raise AccountError("invalid_credentials") from exc
            expected = row["password_hash"]
            actual = _hash_password(password or "", salt)
            if not hmac.compare_digest(expected, actual):
                raise AccountError("invalid_credentials")
            token = secrets.token_urlsafe(40)
            stamp = _now()
            expires = stamp + timedelta(days=_SESSION_DAYS)
            con.execute(
                "DELETE FROM app_sessions WHERE expires_at<=?",
                (_iso(stamp),),
            )
            con.execute(
                """INSERT INTO app_sessions(token_hash,account_id,expires_at,created_at)
                VALUES(?,?,?,?)""",
                (_token_hash(token), row["id"], _iso(expires), _iso(stamp)),
            )
            return {
                "access_token": token,
                "expires_at": _iso(expires),
                "account": self._payload(row),
            }

    def session(self, token):
        if not token:
            return None
        with self._db() as con:
            row = con.execute(
                """SELECT a.*,s.expires_at AS session_expires
                FROM app_sessions s
                JOIN app_accounts a ON a.id=s.account_id
                WHERE s.token_hash=?""",
                (_token_hash(token),),
            ).fetchone()
            if row is None:
                return None
            if _parse(row["session_expires"]) <= _now():
                con.execute(
                    "DELETE FROM app_sessions WHERE token_hash=?",
                    (_token_hash(token),),
                )
                return None
            return self._payload(row)

    def logout(self, token):
        if not token:
            return
        with self._db() as con:
            con.execute(
                "DELETE FROM app_sessions WHERE token_hash=?",
                (_token_hash(token),),
            )

    def request_recovery(self, email):
        email = (email or "").strip().lower()
        with self._db() as con:
            row = con.execute(
                "SELECT * FROM app_accounts WHERE email=?", (email,)
            ).fetchone()
            if row is None or row["telegram_id"] is None:
                return None
            alphabet = string.ascii_uppercase + string.digits
            code = "".join(secrets.choice(alphabet) for _ in range(8))
            stamp = _now()
            con.execute(
                "DELETE FROM app_recovery_codes WHERE account_id=? OR expires_at<=?",
                (row["id"], _iso(stamp)),
            )
            con.execute(
                """INSERT INTO app_recovery_codes
                (code_hash,account_id,expires_at,used_at,created_at)
                VALUES(?,?,?,?,?)""",
                (
                    _token_hash(code),
                    row["id"],
                    _iso(stamp + timedelta(minutes=_RECOVERY_MINUTES)),
                    None,
                    _iso(stamp),
                ),
            )
            return {"telegram_id": int(row["telegram_id"]), "code": code}

    def confirm_recovery(self, email, code, new_password):
        email = (email or "").strip().lower()
        code = (code or "").strip().upper()
        if len(new_password or "") < 8 or len(new_password) > 128:
            raise AccountError("invalid_password")
        with self._db() as con:
            row = con.execute(
                """SELECT a.id AS account_id,r.code_hash,r.expires_at,r.used_at
                FROM app_accounts a
                JOIN app_recovery_codes r ON r.account_id=a.id
                WHERE a.email=? AND r.code_hash=?""",
                (email, _token_hash(code)),
            ).fetchone()
            if row is None or row["used_at"] is not None:
                raise AccountError("invalid_recovery_code")
            if _parse(row["expires_at"]) <= _now():
                raise AccountError("expired_recovery_code")
            salt = secrets.token_bytes(16)
            stamp = _iso(_now())
            con.execute(
                """UPDATE app_accounts
                SET password_salt=?,password_hash=?,updated_at=?
                WHERE id=?""",
                (
                    salt.hex(),
                    _hash_password(new_password, salt),
                    stamp,
                    row["account_id"],
                ),
            )
            con.execute(
                "UPDATE app_recovery_codes SET used_at=? WHERE code_hash=?",
                (stamp, row["code_hash"]),
            )
            con.execute(
                "DELETE FROM app_sessions WHERE account_id=?",
                (row["account_id"],),
            )

    @staticmethod
    def _merge_telegram_entitlement(row, status, expires_at):
        """Linking a bot must never erase a POTV trial or paid subscription.

        Only a *valid paid* Telegram entitlement may extend an existing
        account. Manual POTV approvals remain authoritative; inactive bot
        state does not downgrade a customer or reset the five-day trial.
        """
        current_status = row["subscription_status"] or "free"
        current_expiry = row["subscription_expires_at"]
        candidate = subscription_state(status, expires_at)
        current = subscription_state(current_status, current_expiry)
        if (str(status or "").lower() == "active" and
                candidate["access_allowed"] and
                (not current["access_allowed"] or
                 aware(expires_at) > aware(current_expiry))):
            return "active", candidate["subscription_expires_at"]
        return current_status, current_expiry

    def link_telegram(self, account_id, telegram_id, status, expires_at):
        with self._db() as con:
            current = con.execute(
                "SELECT * FROM app_accounts WHERE id=?", (account_id,)
            ).fetchone()
            if current is None:
                raise AccountError("account_not_found")
            merged_status, merged_expiry = self._merge_telegram_entitlement(
                current, status, expires_at
            )
            con.execute(
                "UPDATE app_accounts SET telegram_id=NULL WHERE telegram_id=? AND id<>?",
                (int(telegram_id), account_id),
            )
            con.execute(
                """UPDATE app_accounts
                SET telegram_id=?,subscription_status=?,
                    subscription_expires_at=?,updated_at=?
                WHERE id=?""",
                (int(telegram_id), merged_status, merged_expiry,
                 _iso(_now()), account_id),
            )
            row = con.execute(
                "SELECT * FROM app_accounts WHERE id=?", (account_id,)
            ).fetchone()
            return self._payload(row)

    def update_subscription_for_telegram(self, telegram_id, status, expires_at):
        with self._db() as con:
            row = con.execute(
                "SELECT * FROM app_accounts WHERE telegram_id=?",
                (int(telegram_id),),
            ).fetchone()
            if row is None:
                return
            merged_status, merged_expiry = self._merge_telegram_entitlement(
                row, status, expires_at
            )
            con.execute(
                """UPDATE app_accounts
                SET subscription_status=?,subscription_expires_at=?,updated_at=?
                WHERE telegram_id=?""",
                (merged_status, merged_expiry, _iso(_now()), int(telegram_id)),
            )

    def account_by_email(self, email):
        email = (email or "").strip().lower()
        if not _EMAIL_RE.match(email):
            raise AccountError("invalid_email")
        with self._db() as con:
            row = con.execute(
                "SELECT * FROM app_accounts WHERE email=?", (email,)
            ).fetchone()
            return self._payload(row)

    def activate_manual(
        self, email, *, approved_by, payment_confirmed=False,
        payment_reference=None, payment_paid_at=None, at=None
    ):
        """One paid calendar month, following current term if still active.

        Only call after human payment approval. Not reachable from user API.
        """
        email = (email or "").strip().lower()
        if not _EMAIL_RE.match(email):
            raise AccountError("invalid_email")
        if not payment_confirmed or not str(approved_by or "").strip():
            raise AccountError("payment_approval_required")
        reference = str(payment_reference or "").strip() or None
        if reference is not None and len(reference) > 160:
            raise AccountError("invalid_payment_reference")
        stamp = aware(at) if at is not None else _now()
        if stamp is None:
            raise AccountError("invalid_activation_date")
        paid_at = aware(payment_paid_at) if payment_paid_at is not None else None
        if payment_paid_at is not None and paid_at is None:
            raise AccountError("invalid_payment_date")
        with self._db() as con:
            row = con.execute(
                "SELECT * FROM app_accounts WHERE email=?", (email,)
            ).fetchone()
            if row is None:
                raise AccountError("account_not_found")
            prev_expiry = aware(row["subscription_expires_at"])
            extending = (
                row["subscription_status"] == "active"
                and prev_expiry is not None and prev_expiry > stamp
            )
            start = prev_expiry if extending else stamp
            billing_day = (
                row["subscription_billing_day"] if extending
                and row["subscription_billing_day"] else
                start.astimezone(LOCAL_TZ).day
            )
            new_expiry = monthly_expiry(start, billing_day)
            if reference is None:
                # A duplicate chat instruction must not add another free month.
                latest = con.execute(
                    """SELECT approved_at FROM app_manual_activations
                    WHERE account_id=? ORDER BY id DESC LIMIT 1""",
                    (row["id"],)
                ).fetchone()
                if latest and stamp - aware(latest["approved_at"]) < timedelta(hours=24):
                    raise AccountError("duplicate_manual_approval")
            try:
                con.execute(
                    """INSERT INTO app_manual_activations(
                       account_id,payment_reference,payment_paid_at,approved_by,
                       approved_at,starts_at,previous_expires_at,new_expires_at
                    ) VALUES(?,?,?,?,?,?,?,?)""",
                    (row["id"], reference,
                     _iso(paid_at) if paid_at else None,
                     str(approved_by).strip(), _iso(stamp), _iso(start),
                     row["subscription_expires_at"], _iso(new_expiry))
                )
            except sqlite3.IntegrityError as exc:
                raise AccountError("duplicate_payment_reference") from exc
            con.execute(
                """UPDATE app_accounts SET subscription_status='active',
                subscription_expires_at=?,subscription_billing_day=?,updated_at=?
                WHERE id=?""",
                (_iso(new_expiry), billing_day, _iso(stamp), row["id"])
            )
            updated = con.execute(
                "SELECT * FROM app_accounts WHERE id=?", (row["id"],)
            ).fetchone()
            return self._payload(updated)