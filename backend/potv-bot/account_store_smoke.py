import os,tempfile
from account_store import AccountStore,AccountError
fd,path=tempfile.mkstemp(suffix=".sqlite3")
os.close(fd)
try:
    store=AccountStore(path); store.init()
    account=store.register("qa@example.com","StrongPass123!","QA")
    login=store.login("qa@example.com","StrongPass123!")
    assert store.session(login["access_token"])["id"]==account["id"]
    store.link_telegram(account["id"],999000111,"active","2030-01-01T00:00:00+00:00")
    linked=store.session(login["access_token"])
    assert linked["telegram_chat_id"]=="999000111"
    rec=store.request_recovery("qa@example.com")
    assert rec and rec["code"]
    store.confirm_recovery("qa@example.com",rec["code"],"NewStrongPass123!")
    assert store.session(login["access_token"]) is None
    assert store.login("qa@example.com","NewStrongPass123!")["account"]["id"]==account["id"]
    print("PASS account store")
finally:
    try: os.remove(path)
    except OSError: pass
