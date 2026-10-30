"""POTV Telegram bot offline regression: no real Telegram, bank or production DB."""
import json
import os
import sqlite3
import tempfile
from datetime import datetime, timedelta, timezone
from unittest.mock import patch
# Use a fictional group in offline QA; never depend on production IDs.
os.environ['POTV_GROUP_CHAT_ID'] = '-1000000007777'
os.environ['POTV_GROUP_INVITE_URL'] = 'https://t.me/example'
from potv_ops import install
from potv_payments import latest_apk

def run():
    out, approvals = [], []
    with tempfile.TemporaryDirectory() as d:
        path = os.path.join(d,"qa.sqlite3")
        def dbc():
            con = sqlite3.connect(path)
            con.row_factory=sqlite3.Row
            return con
        with dbc() as c:
            c.executescript("""CREATE TABLE payments (
            id INTEGER PRIMARY KEY AUTOINCREMENT, telegram_id INTEGER NOT NULL,
            reference TEXT UNIQUE NOT NULL,photo_file_id TEXT,
            status TEXT DEFAULT 'pending',created_at TEXT NOT NULL,reviewed_at TEXT);
            CREATE TABLE subscriptions (
            telegram_id INTEGER PRIMARY KEY, status TEXT,starts_at TEXT,expires_at TEXT,updated_at TEXT);
            CREATE TABLE users (
            telegram_id INTEGER PRIMARY KEY,first_name TEXT,username TEXT);
            CREATE TABLE app_accounts (
            telegram_id INTEGER,email TEXT);
            """)
            c.execute("INSERT INTO payments(telegram_id,reference,status,created_at) VALUES(123,'LEGACY','pending','2026-10-14T10:00:00+00:00')")
        class FakeAccounts:
            def account_by_email(self,email):
                if email == "cliente@example.com":
                    return {"id":"abc", "email": email, "telegram_chat_id": None}
                return None
            def activate_manual(self,email,**kwargs):
                assert kwargs["payment_confirmed"] is True
                assert kwargs["approved_by"] == "telegram:777"
                assert kwargs["payment_reference"].startswith("potv-telegram-")
                approvals.append((email,kwargs))
                return {"subscription_expires_at":
                        (datetime.now(timezone.utc)+timedelta(days=30)).isoformat()}
        def fake_tg(method,payload):
            out.append((method,payload))
            if method == "getChatAdministrators":
                assert str(payload["chat_id"])=="-1000000007777"
                return {"result":[{"status":"creator","user":{"id":777}}]}
            if method == "getChatMember":
                return {"result":{"status":"member"}}
            return {"ok":True,"result":{"message_id":len(out)}}
        def old(message):
            raise AssertionError("unexpected old bot handler")
        now=lambda:datetime.now(timezone.utc)
        def record_user(user):
            with dbc() as db:
                db.execute('INSERT OR REPLACE INTO users VALUES(?,?,?)',(user['id'],user.get('first_name'),user.get('username')))
        deps=dict(tg=fake_tg,dbc=dbc,handle_message=old,now=now,
                  upsert_user=record_user,
                  iso=lambda d:d.isoformat(),ADMIN="",BOT_USER="potvoficialbot",
                  BOT_ID="8938958703",PLAN_TEXT="QA",PAYMENT_TEXT="Pago QA",
                  ACCOUNT_STORE=FakeAccounts())
        handle, cmds = install(deps)
        def inbound(uid,txt="",**kwargs):
            message={"chat":{"id":uid,"type":"private"},"from":{"id":uid}, "text":txt}
            message.update(kwargs)
            handle(message)
        def text_for(uid):
            return [p["text"] for k,p in out if k=="sendMessage" and p.get("chat_id")==uid]
        inbound(777,"/activaradmin")
        inbound(123,"/start")
        with patch("potv_ops.latest_apk",return_value=("v9.9","https://github.com/ricardoaldape/POTV/releases/download/v9.9/actual.apk")):
            inbound(123,"📥 Descargar aplicación")
        assert "v9.9" in text_for(123)[-1]
        assert "Descargar APK más reciente" in json.loads(out[-1][1]["reply_markup"])["inline_keyboard"][0][0]["text"]
        inbound(123,"/approve 1")
        assert not approvals, "legacy proof without data must not activate"
        inbound(123,"/pago")
        inbound(123,"cliente@example.com")
        inbound(123,"", photo=[{"file_id":"photo-abc","file_unique_id":"unique-photo-17","file_size":2400}])
        with dbc() as db:
            rows=db.execute("SELECT id,status FROM payments ORDER BY id").fetchall()
            assert len(rows)==2 and rows[1]["status"]=="pending"
            pid=rows[1]["id"]
        assert not approvals, "sending a receipt must not trigger activation"
        inbound(123,"/approve "+str(pid))
        assert not approvals, "unauthorized customer approval blocked"
        inbound(777,"/verpago "+str(pid))
        assert any(k=="sendPhoto" and v["chat_id"]==777 for k,v in out)
        inbound(777,"/approve 1")
        assert not approvals, "incomplete old payment blocked"
        inbound(777,"/approve "+str(pid))
        assert len(approvals)==1, "one approval only"
        inbound(777,"/approve "+str(pid))
        assert len(approvals)==1, "double approval blocked"
        with dbc() as db:
            row=db.execute("SELECT status,reviewed_at FROM payments WHERE id=?",(pid,)).fetchone()
            assert row["status"]=="approved" and row["reviewed_at"]
        inbound(123,"/pago")
        inbound(123,"cliente@example.com")
        inbound(123,"",photo=[{"file_id":"photo-abc","file_unique_id":"unique-photo-17"}])
        with dbc() as db:
            assert db.execute("SELECT COUNT(*) FROM payments").fetchone()[0]==2
        inbound(123,"/pago")
        inbound(123,"cliente@example.com")
        inbound(123,"",document={"file_id":"document-pdf-1","file_unique_id":"pdf1","mime_type":"application/pdf"})
        with dbc() as db:
            rejection_id=db.execute("SELECT max(id) FROM payments").fetchone()[0]
        inbound(777,"/reject "+str(rejection_id))
        with dbc() as db:
            assert db.execute("SELECT status FROM payments WHERE id=?",(rejection_id,)).fetchone()[0]=="rejected"
        assert len(approvals)==1
        assert any(cmd["command"]=="descargar" for cmd in cmds)
        inbound(123,"/comprar");inbound(123,"/comprar")
        with dbc() as db:
            assert db.execute("SELECT COUNT(*) FROM support_tickets").fetchone()[0]==1
        inbound(777,"/anuncio Comunidad oficial")
        assert any(str(p.get("chat_id"))=="-1000000007777" for k,p in out if k=="sendMessage")
        print("PASS Telegram: latest APK, payment metadata, manual approval, private preview, role enforcement, idempotence, rejection, PDF")
    # GitHub query newest published APK, rejects stale fallback
    releases=[{"published_at":"2026-10-01T00:00:00Z","draft":False,"tag_name":"old",
               "assets":[{"browser_download_url":"https://github.com/ricardoaldape/POTV/releases/download/old/old.apk","size":10000000}]},
              {"published_at":"2026-10-16T00:00:00Z","draft":False,"tag_name":"new",
               "assets":[{"browser_download_url":"https://github.com/ricardoaldape/POTV/releases/download/new/new.apk","size":10000000}]}]
    class FakeResponse:
        def __enter__(self):return self
        def __exit__(self,*a):pass
        def read(self):return json.dumps(releases).encode()
    with patch("potv_payments.urlopen",return_value=FakeResponse()):
        version,link=latest_apk()
        assert version=="new" and link.endswith("/new/new.apk")
    with patch("potv_payments.urlopen",side_effect=OSError("GitHub down")):
        version,link=latest_apk()
        assert version is None and link.endswith("/releases")
    print("PASS GitHub: newest published asset, no old APK on API failure")

if __name__ == "__main__":
    run()
