"""Isolated end-to-end Telegram/POTV account linking tests."""
import os, tempfile, json, threading, urllib.request, urllib.error
from http.server import ThreadingHTTPServer
from contextlib import contextmanager

@contextmanager
def isolated_api():
    with tempfile.TemporaryDirectory(prefix="potv-link-qa-") as temp:
        os.environ["POTV_DB"]=os.path.join(temp,"qa.db")
        os.environ["POTV_SUPABASE_MODE"]="local"
        import app
        app.init_db()
        server=ThreadingHTTPServer(("127.0.0.1",0),app.ApiHandler)
        thread=threading.Thread(target=server.serve_forever,daemon=True)
        thread.start()
        try:
            yield app, "http://127.0.0.1:"+str(server.server_port)
        finally:
            server.shutdown()
            thread.join(timeout=4)
            server.server_close()

def request(base, path, body=None, bearer=None):
    headers={"Content-Type":"application/json"}
    if bearer: headers["Authorization"]="Bearer "+bearer
    req=urllib.request.Request(base+path,
         headers=headers, data=json.dumps(body).encode() if body is not None else None,
         method="POST" if body is not None else "GET")
    try:
        with urllib.request.urlopen(req,timeout=5) as r:
            return r.status,json.load(r)
    except urllib.error.HTTPError as error:
        return error.code,json.load(error)

def run():
    with isolated_api() as (app,base):
        tid=987123
        app.upsert_user({"id":tid,"username":"qa","first_name":"QA"})
        status,new=request(base,"/api/v1/account/register",
                           {"email":"qa@example.com","password":"VerySecureQa_555","name":"Tester"})
        assert status==201,(status,new)
        status,login=request(base,"/api/v1/account/login",
                            {"email":"qa@example.com","password":"VerySecureQa_555"})
        assert status==200
        session=login["access_token"]
        original_exp=login["account"]["subscription_expires_at"]
        assert login["account"]["subscription_status"]=="trial"
        code=app.make_link_code(tid)
        status,unauthed=request(base,"/api/v1/link/claim",{"code":code,"device_id":"qa-device"})
        assert status==401 and unauthed["error"]=="account_login_required",(status,unauthed)
        with app.dbc() as db:
            assert db.execute("SELECT used_at FROM link_codes WHERE code=?",(code,)).fetchone()[0] is None
            assert db.execute("SELECT COUNT(*) FROM licenses WHERE telegram_id=?",(tid,)).fetchone()[0]==0
        status,bad=request(base,"/api/v1/link/claim",{"code":code,"device_id":"qa-device"}, "incorrect-token")
        assert status==401 and bad["error"]=="invalid_session"
        status,linked=request(base,"/api/v1/link/claim",
                              {"code":code.lower(),"device_id":"qa-device"},session)
        assert status==200 and linked["ok"] and linked["status"]=="trial"
        assert linked["account"]["subscription_expires_at"]==original_exp
        assert linked["account"]["telegram_chat_id"]==str(tid)
        status,snapshot=request(base,"/api/v1/account/session",bearer=session)
        assert status==200 and snapshot["account"]["telegram_chat_id"]==str(tid)
        status,lic=request(base,"/api/v1/license/status",bearer=linked["license_token"])
        assert status==200 and lic["status"]=="trial"
        status,reused=request(base,"/api/v1/link/claim",
                              {"code":code,"device_id":"qa-device-2"},session)
        assert status==400 and reused["error"]=="invalid_or_expired_code"
        with app.dbc() as db:
            assert db.execute("SELECT COUNT(*) FROM licenses WHERE telegram_id=?",(tid,)).fetchone()[0]==1
            db.execute("""UPDATE app_accounts SET subscription_status='active',
                subscription_expires_at='9999-12-31T23:59:59+00:00'
                WHERE email='qa@example.com'""")
        assert app.subscription(tid)["status"]=="active"
        again=app.make_link_code(tid)
        status,relinked=request(base,"/api/v1/link/claim",
                                {"code":again,"device_id":"qa-device"},session)
        assert status==200 and relinked["status"]=="active"
        assert relinked["expires_at"].startswith("9999-")
        status,botlicense=request(base,"/api/v1/license/status",bearer=relinked["license_token"])
        assert status==200 and botlicense["status"]=="active"
        print("PASS isolated linking: auth before claim, atomic account association, trial unchanged, used-code blocked, paid/permanent retained, bot/license status synchronized")

if __name__=="__main__":
    run()
