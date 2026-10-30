"""Offline POTV account registration/owner-only metrics regression tests."""
import os
import sqlite3
import tempfile
from datetime import datetime, timedelta, timezone

def run():
    with tempfile.TemporaryDirectory(prefix="potv-private-stats-") as root:
        from account_store import AccountStore, AccountError
        from potv_stats import snapshot, report, deliver
        os.environ['POTV_GROUP_CHAT_ID'] = '-1000000007777'
        from potv_ops import install
        dbpath = os.path.join(root,"test.sqlite3")
        store=AccountStore(dbpath)
        store.init()
        def dbc():
            con=sqlite3.connect(dbpath)
            con.row_factory=sqlite3.Row
            return con
        with dbc() as db:
            db.executescript("""
              CREATE TABLE users(telegram_id INTEGER PRIMARY KEY,
                first_name TEXT, username TEXT);
              CREATE TABLE payments(id INTEGER PRIMARY KEY AUTOINCREMENT,
                telegram_id INTEGER NOT NULL,reference TEXT,
                photo_file_id TEXT,status TEXT NOT NULL DEFAULT 'pending',
                created_at TEXT,reviewed_at TEXT);
              CREATE TABLE subscriptions(telegram_id INTEGER PRIMARY KEY,
                status TEXT,starts_at TEXT,expires_at TEXT,updated_at TEXT);
              CREATE TABLE licenses(telegram_id INTEGER,device_id TEXT);
            """)
        new = store.register("new.client@example.com","secureTest987","Cliente de prueba")
        assert new["subscription_status"]=="trial"
        with dbc() as db:
            assert db.execute("SELECT COUNT(*) FROM bot_account_registration_events").fetchone()[0]==1
        try:
            store.register("new.client@example.com","secureTest987","Otro nombre")
            raise AssertionError("duplicate should fail")
        except AccountError as err:
            assert err.code=="account_exists"
        with dbc() as db:
            assert db.execute("SELECT COUNT(*) FROM bot_account_registration_events").fetchone()[0]==1
        m=snapshot(dbc)
        assert m["registered"]==1 and m["trial_current"]==1
        assert m["access_current"]==1 and m["active_7d"]==0
        login=store.login("new.client@example.com","secureTest987")
        m=snapshot(dbc)
        assert m["active_7d"]==1
        assert store.session(login["access_token"])["email"]=="new.client@example.com"
        old = store.register("previous@example.com","secureTest888","Test anterior")
        with dbc() as db:
            db.execute("""UPDATE app_accounts SET subscription_status='active',
                 subscription_expires_at='9999-12-31T23:59:59+00:00'
                 WHERE id=?""",(old["id"],))
            db.execute("UPDATE bot_account_registration_events SET delivered_at=? WHERE account_id=?",
                       (datetime.now(timezone.utc).isoformat(),old["id"]))
        stats=snapshot(dbc)
        assert stats["registered"]==2 and stats["access_current"]==2
        assert stats["trial_current"]==1 and stats["paid_current"]==1
        assert stats["new_24h"]==2 and stats["active_7d"]==1
        assert "Cuentas registradas: 2" in report(dbc)

        sent=[]
        def fake_tg(method,payload):
            if method=="getChatAdministrators":
                return {"result":[{"status":"creator","user":{"id":777}}]}
            assert method=="sendMessage"
            sent.append(payload)
            return {"ok":True,"result":{"message_id":len(sent)}}
        def record_user(user):
            with dbc() as db:
                db.execute("""INSERT OR REPLACE INTO users(telegram_id,
                    first_name,username) VALUES(?,?,?)""",
                    (user["id"],user.get("first_name"),user.get("username")))
        g=dict(dbc=dbc,tg=fake_tg,handle_message=lambda message:None,
               ADMIN="",now=lambda:datetime.now(timezone.utc),
               iso=lambda dt:dt.isoformat(),upsert_user=record_user,
               ACCOUNT_STORE=store,PAYMENT_TEXT="test",PLAN_TEXT="test",
               BOT_USER="potvoficialbot",BOT_ID="8938958703")
        handle, cmds=install(g)
        def send(uid,message):
            handle({"from":{"id":uid},"chat":{"id":uid,"type":"private"},"text":message})
        send(123,"/estadisticas")
        assert "reservado" in sent[-1]["text"] and "registradas" not in sent[-1]["text"]
        assert sent[-1]["chat_id"]==123
        sent.clear()
        assert deliver(dbc,fake_tg,lambda:[777],lambda x:False)==0
        assert not sent
        assert deliver(dbc,fake_tg,lambda:[777],lambda x:x==777)==1
        assert len(sent)==1 and sent[0]["chat_id"]==777
        assert "new.client@example.com" in sent[0]["text"]
        assert "previous@example.com" not in sent[0]["text"]
        assert deliver(dbc,fake_tg,lambda:[777],lambda x:True)==0
        assert len(sent)==1, "no duplicate delivery"
        send(777,"/activaradmin")
        send(777,"/estadisticas")
        assert "Cuentas registradas: 2" in sent[-1]["text"]
        assert sent[-1]["chat_id"]==777
        assert all(p["chat_id"]>0 for p in sent), "no data in groups"
        assert all(cmd["command"]!="estadisticas" for cmd in cmds), "admin-only command is not in public menu"
        assert not any("secureTest" in p["text"] for p in sent)
        print("PASS private registration notifications, no duplicates, access vs activity metrics, authorization, no group/public leaks")


if __name__=="__main__":
    run()
