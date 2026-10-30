import os
import tempfile
from account_store import AccountStore, AccountError

fd,path=tempfile.mkstemp(prefix="potv-account-",suffix=".sqlite3")
os.close(fd)
try:
    store=AccountStore(path)
    store.init()
    acct=store.register("qa@example.com","Potv-Test-123!","QA")
    assert acct["email"]=="qa@example.com"
    try:
        store.register("qa@example.com","Potv-Test-123!","QA2")
        raise AssertionError("duplicate accepted")
    except AccountError as exc:
        assert exc.code=="account_exists"
    session=store.login("qa@example.com","Potv-Test-123!")
    token=session["access_token"]
    assert store.session(token)["id"]==acct["id"]
    linked=store.link_telegram(acct["id"],123456,"active","2030-01-01T00:00:00+00:00")
    assert linked["telegram_chat_id"]=="123456"
    recovery=store.request_recovery("qa@example.com")
    assert recovery and recovery["telegram_id"]==123456
    store.confirm_recovery("qa@example.com",recovery["code"],"Potv-Test-456!")
    assert store.session(token) is None
    session2=store.login("qa@example.com","Potv-Test-456!")
    store.logout(session2["access_token"])
    assert store.session(session2["access_token"]) is None
    print("PASS: register/login/session/link/recovery/logout")
finally:
    for suffix in ("","-shm","-wal"):
        try: os.remove(path+suffix)
        except FileNotFoundError: pass
