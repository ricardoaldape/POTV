"""Offline regression test: never calls real Telegram or modifies production DB."""
import os
import sqlite3
import tempfile
from datetime import datetime, timezone
from potv_ops import install

def run():
    output = []
    with tempfile.TemporaryDirectory() as directory:
        path = os.path.join(directory, "qa.sqlite3")
        def connect():
            db = sqlite3.connect(path)
            db.row_factory = sqlite3.Row
            return db
        with connect() as c:
            c.execute("""CREATE TABLE payments (
                id INTEGER PRIMARY KEY, telegram_id INTEGER, reference TEXT,
                status TEXT, reviewed_at TEXT)""")
            c.execute("INSERT INTO payments VALUES(1,123,'TEST','pending',NULL)")
        def fake_telegram(method, payload):
            output.append((method, payload))
            if method == "getChatMember":
                return {"result": {"status": "creator"
                    if payload["user_id"] == 777 else "member"}}
            return {"ok": True, "result": {"message_id": 1}}
        clock = lambda: datetime.now(timezone.utc)
        deps = dict(tg=fake_telegram, dbc=connect,
                    handle_message=lambda message: None, now=clock,
                    iso=lambda stamp: stamp.isoformat(), ADMIN="",
                    BOT_USER="potvoficialbot", BOT_ID="8938958703",
                    PLAN_TEXT="Plan QA", PAYMENT_TEXT="Pago QA",
                    activate=lambda telegram_id, days: clock())
        handle, commands = install(deps)
        def inbound(user_id, text, chat_id=None, chat_type="private"):
            handle({"chat": {"id": chat_id or user_id, "type": chat_type},
                    "from": {"id": user_id}, "text": text})
        inbound(123, "/start")
        inbound(123, "/comprar")
        inbound(123, "/comprar")
        with connect() as c:
            assert c.execute("SELECT COUNT(*) FROM support_tickets").fetchone()[0] == 1
        inbound(123, "/activaradmin")
        inbound(777, "/activaradmin")
        inbound(123, "/approve 1")
        with connect() as c:
            assert c.execute("SELECT status FROM payments").fetchone()[0] == "pending"
        inbound(777, "/approve 1")
        with connect() as c:
            assert c.execute("SELECT status FROM payments").fetchone()[0] == "approved"
        inbound(777, "/anuncio Comunidad oficial")
        assert any(str(body.get("chat_id")) == "-5279101330"
                   for method, body in output if method == "sendMessage")
        before = len(output)
        inbound(123, "unrelated group chat",
                chat_id=-5279101330, chat_type="group")
        assert len(output) == before
        assert any(cmd["command"] == "activaradmin" for cmd in commands)
        print("PASS: sales dedup, verified owner, approval authorization,"
              " private-first group behavior, announcements")

if __name__ == "__main__":
    run()