#!/usr/bin/env python3
import os, sys, json, time, sqlite3, secrets, hashlib, threading, uuid
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.request import Request, urlopen
from urllib.error import HTTPError
from urllib.parse import parse_qs, urlencode, urlsplit
from account_store import AccountStore, AccountError
from email_verification import PendingRegistrations, smtp_ready
from content_gateway import ContentGateway, ContentGatewayError
from content_access import has_active_subscription, requires_vod_subscription, catalog_access_status
from catalog_json_transport import encode_catalog

BASE=os.path.dirname(os.path.abspath(__file__))
DB=os.getenv("POTV_DB",os.path.join(BASE,"potv.sqlite3"))
TOKEN=os.getenv("POTV_BOT_TOKEN","").strip()
BOT_USER=os.getenv("BOT_USERNAME","potvoficialbot")
BOT_ID=os.getenv("BOT_ID","8938958703")
ADMIN=os.getenv("ADMIN_TELEGRAM_ID","").strip()
PAYMENT_TEXT=os.getenv("PAYMENT_TEXT","Datos de pago pendientes de configurar.")
PLAN_TEXT=os.getenv("PLAN_TEXT","POTV — acceso por suscripción")
HOST=os.getenv("API_HOST","127.0.0.1")
PORT=int(os.getenv("API_PORT","8093"))
SUPABASE_URL=os.getenv("SUPABASE_URL","").strip().rstrip("/")
SUPABASE_MODE=os.getenv("POTV_SUPABASE_MODE","local").strip().lower()
SUPABASE_KEY=os.getenv("SUPABASE_KEY","").strip()
SUPABASE_KEY_FILE=os.getenv("SUPABASE_KEY_FILE","").strip()
if not SUPABASE_KEY and SUPABASE_KEY_FILE:
    try:
        with open(SUPABASE_KEY_FILE,"r",encoding="utf-8") as fh:
            SUPABASE_KEY=fh.read().strip()
    except OSError:
        SUPABASE_KEY=""

def supabase_enabled():
    return SUPABASE_MODE=="supabase" and bool(SUPABASE_URL and SUPABASE_KEY)

def sb_request(method,table,params=None,body=None,prefer=None):
    if not supabase_enabled():
        raise RuntimeError("Supabase no configurado")
    query=("?"+urlencode(params)) if params else ""
    headers={
        "apikey":SUPABASE_KEY,
        "Authorization":f"Bearer {SUPABASE_KEY}",
        "Content-Type":"application/json",
        "Accept":"application/json",
    }
    if prefer:
        headers["Prefer"]=prefer
    data=None if body is None else json.dumps(body).encode()
    req=Request(f"{SUPABASE_URL}/rest/v1/{table}{query}",
                data=data,headers=headers,method=method)
    with urlopen(req,timeout=30) as resp:
        raw=resp.read()
        return json.loads(raw.decode()) if raw else None

def sb_account(tid):
    rows=sb_request("GET","accounts",{
        "telegram_chat_id":f"eq.{int(tid)}",
        "select":"*",
        "limit":"1",
    })
    return rows[0] if rows else None

def auth_admin_create_user(email,telegram_id,username):
    headers={
        "apikey":SUPABASE_KEY,
        "Authorization":f"Bearer {SUPABASE_KEY}",
        "Content-Type":"application/json",
        "Accept":"application/json",
    }
    payload={
        "email":email,
        "password":secrets.token_urlsafe(32),
        "email_confirm":True,
        "user_metadata":{
            "source":"telegram",
            "telegram_chat_id":str(telegram_id),
            "username":username,
        },
    }
    req=Request(f"{SUPABASE_URL}/auth/v1/admin/users",
                data=json.dumps(payload).encode(),headers=headers,method="POST")
    with urlopen(req,timeout=30) as resp:
        return json.loads(resp.read().decode())

def auth_admin_delete_user(user_id):
    headers={
        "apikey":SUPABASE_KEY,
        "Authorization":f"Bearer {SUPABASE_KEY}",
        "Accept":"application/json",
    }
    req=Request(f"{SUPABASE_URL}/auth/v1/admin/users/{user_id}",
                headers=headers,method="DELETE")
    with urlopen(req,timeout=30) as resp:
        return resp.status in (200,204)

def sb_account_id(account_id):
    rows=sb_request("GET","accounts",{
        "id":f"eq.{account_id}",
        "select":"*",
        "limit":"1",
    })
    return rows[0] if rows else None

def account_payload(row):
    if not row:
        return None
    return {
        "id":str(row.get("id") or ""),
        "email":row.get("email"),
        "username":row.get("username") or row.get("email") or "POTV",
        "telegram_chat_id":None if row.get("telegram_chat_id") is None else str(row.get("telegram_chat_id")),
        "subscription_status":row.get("subscription_status") or "free",
        "subscription_expires_at":row.get("subscription_expires_at"),
    }

def auth_request(method,path,body=None,token=None):
    if not supabase_enabled():
        return 503,{"error":"account_service_unavailable"}
    headers={
        "apikey":SUPABASE_KEY,
        "Content-Type":"application/json",
        "Accept":"application/json",
    }
    if token:
        headers["Authorization"]="Bearer "+token
    else:
        headers["Authorization"]=f"Bearer {SUPABASE_KEY}"
    req=Request(f"{SUPABASE_URL}/auth/v1/{path}",
                data=None if body is None else json.dumps(body).encode(),
                headers=headers,method=method)
    try:
        with urlopen(req,timeout=30) as resp:
            raw=resp.read()
            return resp.status,(json.loads(raw.decode()) if raw else {})
    except HTTPError as exc:
        try:
            raw=exc.read()
            payload=json.loads(raw.decode()) if raw else {}
        except Exception:
            payload={}
        return exc.code,payload

def auth_create_account(email,password,username):
    status,payload=auth_request("POST","admin/users",{
        "email":email,
        "password":password,
        "email_confirm":True,
        "user_metadata":{"source":"potv_app","username":username},
    })
    if status not in (200,201):
        return status,payload
    user_id=str(payload.get("id") or "")
    if not user_id:
        return 502,{"error":"account_create_failed"}
    try:
        sb_request("POST","accounts",None,{
            "id":user_id,
            "email":email,
            "username":username,
            "telegram_chat_id":None,
            "subscription_status":"free",
            "subscription_expires_at":None,
        },"return=minimal")
    except Exception:
        try: auth_admin_delete_user(user_id)
        except Exception: pass
        return 409,{"error":"account_profile_create_failed"}
    return 201,account_payload(sb_account_id(user_id))

def auth_password_login(email,password):
    status,payload=auth_request("POST","token?grant_type=password",{
        "email":email,
        "password":password,
    })
    if status!=200:
        return status,payload
    user=payload.get("user") or {}
    account=sb_account_id(str(user.get("id") or ""))
    return 200,{
        "access_token":payload.get("access_token"),
        "refresh_token":payload.get("refresh_token"),
        "expires_in":payload.get("expires_in"),
        "account":account_payload(account),
    }

def auth_user_from_token(token):
    status,payload=auth_request("GET","user",None,token)
    if status!=200:
        return None
    return payload

def auth_recover_email(email):
    status,payload=auth_request("POST","recover",{"email":email})
    return status,payload

def link_authenticated_account(account_id,telegram_id):
    target=sb_account_id(account_id)
    source=sb_account(telegram_id)
    if not target:
        return None
    if source and str(source.get("id"))!=str(account_id):
        sb_request("PATCH","accounts",{"id":f"eq.{source.get('id')}"},
                   {"telegram_chat_id":None},"return=minimal")
    source_status=(source or {}).get("subscription_status") or "free"
    source_exp=(source or {}).get("subscription_expires_at")
    sb_request("PATCH","accounts",{"id":f"eq.{account_id}"},{
        "telegram_chat_id":int(telegram_id),
        "subscription_status":source_status,
        "subscription_expires_at":source_exp,
    },"return=minimal")
    return sb_account_id(account_id)

def now(): return datetime.now(timezone.utc)
def iso(d): return d.astimezone(timezone.utc).isoformat()
def parse(v): return datetime.fromisoformat(v) if v else None
def dbc():
    c=sqlite3.connect(DB,timeout=20); c.row_factory=sqlite3.Row; return c
ACCOUNT_STORE=AccountStore(DB)
PENDING_EMAIL=PendingRegistrations(DB)
EMAIL_VERIFICATION_ENABLED=os.getenv("POTV_EMAIL_VERIFICATION_ENABLED", "false").lower() in ("1", "true", "yes")
CONTENT_GATEWAY=ContentGateway()

def init_db():
    ACCOUNT_STORE.init()
    PENDING_EMAIL.init()
    with dbc() as c:
        c.executescript("""
        PRAGMA journal_mode=WAL;
        CREATE TABLE IF NOT EXISTS users(
          telegram_id INTEGER PRIMARY KEY, username TEXT, first_name TEXT,
          created_at TEXT NOT NULL, updated_at TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS subscriptions(
          telegram_id INTEGER PRIMARY KEY, plan TEXT DEFAULT 'POTV',
          status TEXT DEFAULT 'inactive', starts_at TEXT, expires_at TEXT,
          updated_at TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS payments(
          id INTEGER PRIMARY KEY AUTOINCREMENT, telegram_id INTEGER NOT NULL,
          reference TEXT UNIQUE NOT NULL, photo_file_id TEXT,
          status TEXT DEFAULT 'pending', created_at TEXT NOT NULL, reviewed_at TEXT);
        CREATE TABLE IF NOT EXISTS link_codes(
          code TEXT PRIMARY KEY, telegram_id INTEGER NOT NULL,
          expires_at TEXT NOT NULL, used_at TEXT);
        CREATE TABLE IF NOT EXISTS licenses(
          id INTEGER PRIMARY KEY AUTOINCREMENT, telegram_id INTEGER NOT NULL,
          device_id TEXT NOT NULL, token_hash TEXT UNIQUE NOT NULL,
          created_at TEXT NOT NULL, last_seen TEXT NOT NULL,
          UNIQUE(telegram_id,device_id));
        """)
def upsert_user(u):
    tid=int(u["id"]); ts=iso(now())
    if supabase_enabled():
        username=u.get("username") or u.get("first_name") or f"telegram_{tid}"
        account=sb_account(tid)
        if account:
            sb_request("PATCH","accounts",
                       {"telegram_chat_id":f"eq.{tid}"},
                       {"username":username},
                       "return=minimal")
        else:
            email=f"telegram_{tid}@potv.local"
            auth_user=auth_admin_create_user(email,tid,username)
            account_id=auth_user["id"]
            try:
                sb_request("POST","accounts",None,{
                    "id":account_id,
                    "email":email,
                    "username":username,
                    "telegram_chat_id":tid,
                    "subscription_status":"free",
                    "subscription_expires_at":None,
                },"return=minimal")
            except Exception:
                try: auth_admin_delete_user(account_id)
                except Exception: pass
                raise
        return tid
    with dbc() as c:
        c.execute("""INSERT INTO users VALUES(?,?,?,?,?)
        ON CONFLICT(telegram_id) DO UPDATE SET username=excluded.username,
        first_name=excluded.first_name,updated_at=excluded.updated_at""",
        (tid,u.get("username"),u.get("first_name"),ts,ts))
        c.execute("INSERT OR IGNORE INTO subscriptions(telegram_id,updated_at) VALUES(?,?)",(tid,ts))
    return tid

def subscription(tid):
    # The POTV account is authoritative once Telegram has been linked.
    # An older inactive bot subscription must never override an active
    # customer trial, paid term or permanent owner entitlement.
    if not supabase_enabled():
        with dbc() as c:
            linked=c.execute("""SELECT subscription_status,subscription_expires_at
                FROM app_accounts WHERE telegram_id=?""",(int(tid),)).fetchone()
        if linked:
            from subscription_policy import subscription_state
            state=subscription_state(linked["subscription_status"],
                                     linked["subscription_expires_at"])
            return {"status":state["subscription_status"],"plan":"POTV",
                    "expires_at":state["subscription_expires_at"]}
    if supabase_enabled():
        r=sb_account(tid)
        if not r:
            return {"status":"free","plan":"POTV","expires_at":None}
        st=r.get("subscription_status") or "free"
        exp=parse(r.get("subscription_expires_at"))
        if st=="active" and exp and exp<=now():
            st="expired"
            sb_request("PATCH","accounts",
                       {"telegram_chat_id":f"eq.{int(tid)}"},
                       {"subscription_status":"expired"},
                       "return=minimal")
        return {"status":st,"plan":"POTV","expires_at":r.get("subscription_expires_at")}
    with dbc() as c:
        r=c.execute("SELECT * FROM subscriptions WHERE telegram_id=?",(tid,)).fetchone()
    if not r: return {"status":"inactive","plan":"POTV","expires_at":None}
    st=r["status"]; exp=parse(r["expires_at"])
    if st=="active" and exp and exp<=now():
        st="expired"
        with dbc() as c:
            c.execute("UPDATE subscriptions SET status='expired',updated_at=? WHERE telegram_id=?",(iso(now()),tid))
        ACCOUNT_STORE.update_subscription_for_telegram(tid,"expired",r["expires_at"])
    return {"status":st,"plan":r["plan"],"expires_at":r["expires_at"]}

def activate(tid,days=30):
    s=subscription(tid); base=now(); exp=parse(s["expires_at"])
    if s["status"]=="active" and exp and exp>base: base=exp
    new_exp=base+timedelta(days=days)
    if supabase_enabled():
        if not sb_account(tid):
            upsert_user({"id":tid,"username":f"telegram_{tid}"})
        sb_request("PATCH","accounts",
                   {"telegram_chat_id":f"eq.{int(tid)}"},
                   {"subscription_status":"active",
                    "subscription_expires_at":iso(new_exp)},
                   "return=minimal")
        return new_exp
    with dbc() as c:
        c.execute("""UPDATE subscriptions SET status='active',
        starts_at=COALESCE(starts_at,?),expires_at=?,updated_at=?
        WHERE telegram_id=?""",(iso(now()),iso(new_exp),iso(now()),tid))
    ACCOUNT_STORE.update_subscription_for_telegram(tid,"active",iso(new_exp))
    return new_exp

def make_link_code(tid):
    code=secrets.token_hex(6).upper(); expiry=now()+timedelta(minutes=10)
    if supabase_enabled():
        account=sb_account(tid)
        if not account:
            upsert_user({"id":tid,"username":f"telegram_{tid}"})
            account=sb_account(tid)
        sb_request("DELETE","link_codes",
                   {"telegram_chat_id":f"eq.{int(tid)}"},
                   None,"return=minimal")
        sb_request("POST","link_codes",None,{
            "code":code,
            "account_id":account["id"],
            "telegram_chat_id":tid,
            "expires_at":iso(expiry),
            "used_at":None,
        },"return=minimal")
        return code
    with dbc() as c:
        c.execute("DELETE FROM link_codes WHERE telegram_id=? OR expires_at<?",(tid,iso(now())))
        c.execute("INSERT INTO link_codes(code,telegram_id,expires_at) VALUES(?,?,?)",
                  (code,tid,iso(expiry)))
    return code

def tg(method,payload=None):
    if not TOKEN: raise RuntimeError("POTV_BOT_TOKEN no configurado")
    req=Request(f"https://api.telegram.org/bot{TOKEN}/{method}",
                data=urlencode(payload or {}).encode())
    with urlopen(req,timeout=40) as r: return json.loads(r.read().decode())

KB=json.dumps({"keyboard":[
    [{"text":"📺 Planes"},{"text":"👤 Mi cuenta"}],
    [{"text":"💳 Reportar pago"},{"text":"🔗 Vincular app"}],
    [{"text":"🆘 Soporte"}]],"resize_keyboard":True})
def send(chat_id,text,keyboard=True):
    p={"chat_id":chat_id,"text":text}
    if keyboard: p["reply_markup"]=KB
    return tg("sendMessage",p)

def handle_message(m):
    user=m.get("from") or {}
    if "id" not in user: return
    tid=upsert_user(user); cid=m["chat"]["id"]
    text=(m.get("text") or "").strip()

    if m.get("photo"):
        ref="POTV-"+secrets.token_hex(3).upper()
        with dbc() as c:
            cur=c.execute("""INSERT INTO payments
            (telegram_id,reference,photo_file_id,created_at)
            VALUES(?,?,?,?)""",(tid,ref,m["photo"][-1]["file_id"],iso(now())))
        send(cid,f"✅ Comprobante recibido.\nSolicitud #{cur.lastrowid}\nReferencia: {ref}\nEstado: pendiente.")
        return

    if text in ("/start","/menu"):
        send(cid,f"🏴‍☠️ POTV\nBienvenido. Desde aquí administrarás tu cuenta y la futura vinculación con la app.\n\n@{BOT_USER}")
    elif text=="📺 Planes":
        send(cid,f"📺 {PLAN_TEXT}\n\nPrecio y vigencia se configuran desde el servidor.")
    elif text=="👤 Mi cuenta":
        s=subscription(tid)
        with dbc() as c:
            linked=c.execute("""SELECT email FROM app_accounts
                WHERE telegram_id=?""",(tid,)).fetchone()
        status_label={"active":"Activa","trial":"Prueba de 5 días",
                      "expired":"Vencida","inactive":"Sin activar",
                      "free":"Sin suscripción"}.get(s["status"],s["status"])
        expires=s["expires_at"] or "—"
        if s["status"]=="active" and str(expires).startswith("9999-"):
            expires="Acceso permanente"
        send(cid,"👤 Cuenta POTV\nEstado: "+status_label+
             "\nTelegram: "+("Vinculado" if linked else "Aún no vinculado")+
             (("\nCorreo: "+linked["email"]) if linked else "")+
             "\nVencimiento: "+str(expires))
    elif text=="💳 Reportar pago":
        send(cid,f"💳 Pago / renovación\n\n{PAYMENT_TEXT}\n\nDespués envía aquí la imagen del comprobante.")
    elif text=="🔗 Vincular app":
        code=make_link_code(tid)
        send(cid,"🔗 Código temporal de Telegram: "+code+
             "\nVálido durante 10 minutos. Solo se puede utilizar una vez.\n\n"
             "1. Abre POTV e inicia sesión con tu correo.\n"
             "2. Entra a «Mi cuenta» → «Vincular Telegram».\n"
             "3. Introduce el código anterior.\n\n"
             "La vinculación no cambia tus días de prueba ni tu suscripción.")
    elif text=="🆘 Soporte":
        send(cid,"🆘 Soporte POTV\nDescribe aquí tu problema. Después conectaremos este flujo al panel de soporte.")
    elif text.startswith("/pending") and ADMIN and str(tid)==ADMIN:
        with dbc() as c:
            rows=c.execute("""SELECT id,telegram_id,reference FROM payments
            WHERE status='pending' ORDER BY id LIMIT 20""").fetchall()
        body="\n".join(f"#{r['id']} | {r['telegram_id']} | {r['reference']}" for r in rows) or "Sin pendientes."
        send(cid,"Pendientes:\n"+body,False)
    elif text.startswith("/approve") and ADMIN and str(tid)==ADMIN:
        p=text.split()
        if len(p)<2 or not p[1].isdigit():
            send(cid,"Uso: /approve ID [dias]",False); return
        rid=int(p[1]); days=int(p[2]) if len(p)>2 and p[2].isdigit() else 30
        with dbc() as c:
            row=c.execute("SELECT * FROM payments WHERE id=? AND status='pending'",(rid,)).fetchone()
            if row:
                c.execute("UPDATE payments SET status='approved',reviewed_at=? WHERE id=?",(iso(now()),rid))
        if not row:
            send(cid,"Solicitud no encontrada o ya revisada.",False); return
        expiry=activate(row["telegram_id"],days)
        send(cid,f"✅ Pago #{rid} aprobado hasta {iso(expiry)}",False)
        try: send(row["telegram_id"],f"✅ Suscripción POTV activada.\nVence: {iso(expiry)}")
        except Exception: pass
    elif text.startswith("/reject") and ADMIN and str(tid)==ADMIN:
        p=text.split()
        if len(p)<2 or not p[1].isdigit():
            send(cid,"Uso: /reject ID",False); return
        rid=int(p[1])
        with dbc() as c:
            row=c.execute("SELECT * FROM payments WHERE id=? AND status='pending'",(rid,)).fetchone()
            if row:
                c.execute("UPDATE payments SET status='rejected',reviewed_at=? WHERE id=?",(iso(now()),rid))
        send(cid,"Solicitud rechazada." if row else "Solicitud no encontrada.",False)
    else:
        send(cid,"Usa el menú para administrar tu cuenta POTV.")
from potv_ops import install
handle_message, BOT_COMMANDS = install(globals())

class ApiHandler(BaseHTTPRequestHandler):
    def out(self,code,obj):
        # The authenticated NOVA catalog can exceed 4 MB. Compress it only
        # when the client explicitly accepts gzip; never compress login,
        # entitlement, payment or source-resolution responses.
        catalog = urlsplit(self.path).path in ("/api/v1/content/catalog", "/api/v1/content/media")
        if catalog:
            raw, compressed = encode_catalog(
                obj, self.headers.get("Accept-Encoding", "")
            )
        else:
            raw, compressed = json.dumps(obj).encode(), False
        self.send_response(code)
        self.send_header("Content-Type","application/json")
        self.send_header("Cache-Control","private, no-store")
        if catalog:
            self.send_header("Vary", "Accept-Encoding")
        if compressed:
            self.send_header("Content-Encoding", "gzip")
        self.send_header("Content-Length",str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def log_message(self,fmt,*args):
        return

    def _json_body(self):
        try:
            size=int(self.headers.get("Content-Length","0"))
            if size<0 or size>65536:
                return None
            value=json.loads(self.rfile.read(size) or b"{}")
            return value if isinstance(value,dict) else None
        except Exception:
            return None

    def _bearer(self):
        auth=self.headers.get("Authorization","")
        if not auth.startswith("Bearer "):
            return None
        token=auth[7:].strip()
        return token or None

    def _allow_vod_resolution(self):
        # POTV app accounts are independent of providers. Only the POTV
        # subscription may authorize paid media resolution; provider access
        # is maintained separately on the server. Public-domain VOD remains
        # available unless the operator enables the policy explicitly.
        if not requires_vod_subscription(CONTENT_GATEWAY, os.environ):
            return True
        token = self._bearer()
        if not token:
            self.out(401, {"ok": False, "error": "potv_session_required"})
            return False
        account = ACCOUNT_STORE.session(token)
        if account is None:
            self.out(401, {"ok": False, "error": "potv_invalid_session"})
            return False
        if not has_active_subscription(account):
            self.out(403, {"ok": False, "error": "potv_subscription_required"})
            return False
        return True

    def do_GET(self):
        parsed=urlsplit(self.path)
        path=parsed.path
        query=parse_qs(parsed.query or "")
        def q(name):
            value=(query.get(name) or [""])[0]
            return str(value).strip() or None

        movie_prefixes=(
            "/api/v1/vod/sources/movie/",
            "/api/v1/sources/movie/",
        )
        movie_prefix=next((prefix for prefix in movie_prefixes if path.startswith(prefix)),None)
        if movie_prefix:
            if not self._allow_vod_resolution():
                return
            tmdb_id=path[len(movie_prefix):].strip("/")
            try:
                self.out(200,CONTENT_GATEWAY.resolve_movie(
                    tmdb_id=tmdb_id,
                    title=q("title"),
                    year=q("year"),
                ))
            except ContentGatewayError as exc:
                self.out(exc.status,{"ok":False,"error":exc.code})
            return

        tv_prefixes=(
            "/api/v1/vod/sources/tv/",
            "/api/v1/sources/tv/",
            "/api/v1/sources/anime/",
        )
        tv_prefix=next((prefix for prefix in tv_prefixes if path.startswith(prefix)),None)
        if tv_prefix:
            if not self._allow_vod_resolution():
                return
            tail=path[len(tv_prefix):].strip("/").split("/")
            if len(tail)!=3:
                self.out(400,{"ok":False,"error":"tv_route_requires_id_season_episode"}); return
            tmdb_id,season,episode=tail
            try:
                season=int(season); episode=int(episode)
            except ValueError:
                self.out(400,{"ok":False,"error":"invalid_episode"}); return
            try:
                self.out(200,CONTENT_GATEWAY.resolve_series_episode(
                    tmdb_id=tmdb_id,
                    title=q("title"),
                    year=q("year"),
                    season=season,
                    episode=episode,
                    is_anime=tv_prefix.endswith("/anime/"),
                ))
            except ContentGatewayError as exc:
                self.out(exc.status,{"ok":False,"error":exc.code})
            return

        if path=="/api/v1/content/catalog":
            try:
                # Do not expose signed starter or licensed channel URLs to
                # anonymous, expired, or inactive POTV sessions.
                token=self._bearer()
                account=ACCOUNT_STORE.session(token) if token else None
                status=catalog_access_status(token, account)
                if status != 200:
                    error="invalid_session" if status == 401 else "subscription_required"
                    self.out(status,{"ok":False,"error":error}); return
                self.out(200,CONTENT_GATEWAY.catalog_for_subscriber())
            except ContentGatewayError as exc:
                self.out(exc.status,{"ok":False,"error":exc.code})
            return
        if path=="/api/v1/content/media":
            token=self._bearer()
            account=ACCOUNT_STORE.session(token) if token else None
            status=catalog_access_status(token, account)
            if status != 200:
                error="invalid_session" if status == 401 else "subscription_required"
                self.out(status,{"ok":False,"error":error}); return
            try:
                kind=q("kind")
                offset=int(q("offset") or "0")
                limit=int(q("limit") or "200")
                self.out(200,CONTENT_GATEWAY.media_page(
                    kind=kind, offset=offset, limit=limit
                ))
            except (ValueError, TypeError):
                self.out(400,{"ok":False,"error":"invalid_media_page"})
            except ContentGatewayError as exc:
                self.out(exc.status,{"ok":False,"error":exc.code})
            return
        if path.startswith("/api/v1/content/stream/"):
            target_id=path.rsplit("/",1)[-1].strip()
            if not target_id:
                self.out(404,{"ok":False,"error":"stream_not_found"}); return
            CONTENT_GATEWAY.serve_target(self,target_id,parsed.query)
            return
        if path=="/health":
            self.out(200,{"ok":True,"service":"potv-bot","bot":BOT_USER,"bot_id":BOT_ID})
            return
        if path=="/api/v1/version/latest":
            try:
                with open(os.path.join(BASE,"version.json"),"r",encoding="utf-8") as fh:
                    self.out(200,json.load(fh))
            except Exception:
                self.out(500,{"ok":False,"error":"version_unavailable"})
            return
        if path=="/api/v1/account/session":
            token=self._bearer()
            if not token:
                self.out(401,{"ok":False,"error":"missing_token"}); return
            account=ACCOUNT_STORE.session(token)
            if not account:
                self.out(401,{"ok":False,"error":"invalid_session"}); return
            self.out(200,{"ok":True,"account":account})
            return
        if path=="/api/v1/license/status":
            token=self._bearer()
            if not token:
                self.out(401,{"ok":False,"error":"missing_token"}); return
            token_hash=hashlib.sha256(token.encode()).hexdigest()
            with dbc() as c:
                lic=c.execute("SELECT * FROM licenses WHERE token_hash=?",(token_hash,)).fetchone()
                if lic:
                    c.execute("UPDATE licenses SET last_seen=? WHERE id=?",(iso(now()),lic["id"]))
            if not lic:
                self.out(401,{"ok":False,"error":"invalid_token"}); return
            sub=subscription(lic["telegram_id"])
            self.out(200,{
                "ok":True,
                "valid":sub["status"]=="active",
                "status":sub["status"],
                "plan":sub["plan"],
                "expires_at":sub["expires_at"],
                "account":sub,
            })
            return
        self.out(404,{"ok":False,"error":"not_found"})

    def do_POST(self):
        data=self._json_body()
        if data is None:
            self.out(400,{"ok":False,"error":"bad_json"}); return

        if self.path=="/api/v1/account/email/verify":
            if not EMAIL_VERIFICATION_ENABLED:
                self.out(409,{"ok":False,"error":"verification_disabled"}); return
            try:
                payload=PENDING_EMAIL.verify(str(data.get("email","")),str(data.get("code","")))
            except AccountError as exc:
                self.out(400,{"ok":False,"error":exc.code}); return
            self.out(200,payload); return

        if self.path=="/api/v1/account/email/resend":
            if not EMAIL_VERIFICATION_ENABLED:
                self.out(409,{"ok":False,"error":"verification_disabled"}); return
            try:
                payload=PENDING_EMAIL.resend(str(data.get("email","")))
            except AccountError as exc:
                self.out(429 if exc.code=="verification_rate_limited" else 400,
                         {"ok":False,"error":exc.code}); return
            self.out(202,payload); return

        if self.path=="/api/v1/account/register":
            if EMAIL_VERIFICATION_ENABLED:
                try:
                    payload=PENDING_EMAIL.begin(
                        str(data.get("email","")), str(data.get("password","")),
                        str(data.get("name") or data.get("username") or ""))
                except AccountError as exc:
                    code=503 if exc.code in ("verification_unavailable","verification_delivery_failed") else (429 if exc.code=="verification_rate_limited" else 400)
                    self.out(code,{"ok":False,"error":exc.code}); return
                self.out(202,payload); return
            try:
                account=ACCOUNT_STORE.register(
                    str(data.get("email","")),
                    str(data.get("password","")),
                    str(data.get("name") or data.get("username") or ""),
                )
            except AccountError as exc:
                code=409 if exc.code=="account_exists" else 400
                self.out(code,{"ok":False,"error":exc.code}); return
            self.out(201,{"ok":True,"account":account})
            return

        if self.path=="/api/v1/account/login":
            try:
                payload=ACCOUNT_STORE.login(
                    str(data.get("email","")),
                    str(data.get("password","")),
                )
            except AccountError:
                self.out(401,{"ok":False,"error":"invalid_credentials"}); return
            self.out(200,{"ok":True,**payload})
            return

        if self.path=="/api/v1/account/recover":
            email=str(data.get("email","")).strip().lower()
            recovery=ACCOUNT_STORE.request_recovery(email)
            if recovery:
                try:
                    send(recovery["telegram_id"],
                         "🔐 Recuperación POTV\n\nCódigo: "+
                         recovery["code"]+
                         "\nVálido 15 minutos. No lo compartas con nadie.",
                         True)
                except Exception:
                    pass
            self.out(202,{"ok":True,"status":"accepted"})
            return

        if self.path=="/api/v1/account/recover/confirm":
            try:
                ACCOUNT_STORE.confirm_recovery(
                    str(data.get("email","")),
                    str(data.get("code","")),
                    str(data.get("new_password","")),
                )
            except AccountError as exc:
                self.out(400,{"ok":False,"error":exc.code}); return
            self.out(200,{"ok":True})
            return

        if self.path=="/api/v1/account/logout":
            token=self._bearer()
            if token:
                ACCOUNT_STORE.logout(token)
            self.out(200,{"ok":True})
            return

        if self.path!="/api/v1/link/claim":
            self.out(404,{"ok":False,"error":"not_found"}); return

        code=str(data.get("code","")).upper().strip()
        device_id=str(data.get("device_id","")).strip()
        if not code or not device_id or len(device_id)>200:
            self.out(400,{"ok":False,"error":"code_and_device_required"}); return

        # Linking without a signed-in POTV account previously consumed the
        # Telegram code but created only a device license. Require the email
        # account session BEFORE touching any code or license.
        bearer=self._bearer()
        if not bearer:
            self.out(401,{"ok":False,"error":"account_login_required"}); return
        session_account=ACCOUNT_STORE.session(bearer)
        if not session_account:
            self.out(401,{"ok":False,"error":"invalid_session"}); return
        auth_account_id=session_account["id"]

        linked_account=None
        if supabase_enabled():
            rows=sb_request("GET","link_codes",{
                "code":f"eq.{code}",
                "used_at":"is.null",
                "select":"*",
                "limit":"1",
            })
            row=rows[0] if rows else None
            if not row or parse(row.get("expires_at"))<=now():
                self.out(400,{"ok":False,"error":"invalid_or_expired_code"}); return
            telegram_id=int(row["telegram_chat_id"])
            ts=iso(now())
            if auth_account_id:
                linked_account=link_authenticated_account(auth_account_id,telegram_id)
                if not linked_account:
                    self.out(404,{"ok":False,"error":"account_not_found"}); return
            sb_request("PATCH","link_codes",{"code":f"eq.{code}"},
                       {"used_at":ts},"return=minimal")
            token=secrets.token_urlsafe(32)
            token_hash=hashlib.sha256(token.encode()).hexdigest()
            with dbc() as c:
                c.execute("""INSERT INTO licenses
                (telegram_id,device_id,token_hash,created_at,last_seen)
                VALUES(?,?,?,?,?)
                ON CONFLICT(telegram_id,device_id) DO UPDATE SET
                token_hash=excluded.token_hash,last_seen=excluded.last_seen""",
                (telegram_id,device_id,token_hash,ts,ts))
        else:
            # Claim, app-account association and license must commit together.
            # Never burn a one-time code without linking the signed-in email.
            with dbc() as c:
                c.execute("BEGIN IMMEDIATE")
                row=c.execute("""SELECT * FROM link_codes
                WHERE code=? AND used_at IS NULL""",(code,)).fetchone()
                if not row or parse(row["expires_at"])<=now():
                    self.out(400,{"ok":False,"error":"invalid_or_expired_code"}); return
                telegram_id=int(row["telegram_id"])
                target=c.execute("SELECT * FROM app_accounts WHERE id=?",
                                 (auth_account_id,)).fetchone()
                if not target:
                    self.out(404,{"ok":False,"error":"account_not_found"}); return
                bot=c.execute("""SELECT status,expires_at FROM subscriptions
                                 WHERE telegram_id=?""",(telegram_id,)).fetchone()
                bot_status=bot["status"] if bot else "inactive"
                bot_expiry=bot["expires_at"] if bot else None
                merged_status,merged_expiry=ACCOUNT_STORE._merge_telegram_entitlement(
                    target,bot_status,bot_expiry)
                ts=iso(now())
                c.execute("""UPDATE link_codes SET used_at=?
                    WHERE code=? AND used_at IS NULL""",(ts,code))
                c.execute("""UPDATE app_accounts SET telegram_id=NULL,updated_at=?
                    WHERE telegram_id=? AND id<>?""",
                    (ts,telegram_id,auth_account_id))
                c.execute("""UPDATE app_accounts SET telegram_id=?,
                    subscription_status=?,subscription_expires_at=?,
                    updated_at=? WHERE id=?""",
                    (telegram_id,merged_status,merged_expiry,ts,auth_account_id))
                token=secrets.token_urlsafe(32)
                token_hash=hashlib.sha256(token.encode()).hexdigest()
                c.execute("""INSERT INTO licenses
                (telegram_id,device_id,token_hash,created_at,last_seen)
                VALUES(?,?,?,?,?)
                ON CONFLICT(telegram_id,device_id) DO UPDATE SET
                token_hash=excluded.token_hash,last_seen=excluded.last_seen""",
                (telegram_id,device_id,token_hash,ts,ts))
                linked=c.execute("SELECT * FROM app_accounts WHERE id=?",
                                 (auth_account_id,)).fetchone()
                linked_account=ACCOUNT_STORE._payload(linked)

        if linked_account:
            status=linked_account.get("subscription_status") or "free"
            expires=linked_account.get("subscription_expires_at")
            plan="POTV"
            telegram=str(linked_account.get("telegram_chat_id") or telegram_id)
            account=account_payload(linked_account)
        else:
            sub=subscription(telegram_id)
            status=sub["status"]
            expires=sub["expires_at"]
            plan=sub["plan"]
            telegram=str(telegram_id)
            account=sub
        self.out(200,{
            "ok":True,
            "valid":status=="active",
            "status":status,
            "plan":plan,
            "expires_at":expires,
            "telegram_chat_id":telegram,
            "license_token":token,
            "account":account,
        })

def run_api():
    server=ThreadingHTTPServer((HOST,PORT),ApiHandler)
    server.serve_forever()

def self_test():
    init_db()
    fake={"id":999000111,"username":"selftest","first_name":"Selftest"}
    tid=upsert_user(fake)
    code=make_link_code(tid)
    assert len(code)==12
    assert subscription(tid)["status"] in ("free","inactive","expired")
    print(json.dumps({"ok":True,"db":DB,"link_code_length":len(code)}))
    return 0
def announce_new_version():
    from urllib.parse import urlsplit
    from group_config import GROUP_CHAT_ID
    try:
        with open(os.path.join(BASE,"version.json"),encoding="utf-8") as fh:
            release=json.load(fh)
        version_code=int(release["versionCode"])
        download=release.get("apk_url","")
        with dbc() as c:
            previous=c.execute("""SELECT value FROM bot_runtime
                WHERE key='last_ota_version_code'""").fetchone()
            if previous is None:
                c.execute("INSERT INTO bot_runtime VALUES(?,?)",
                          ("last_ota_version_code",str(version_code)))
                return
            if version_code<=int(previous["value"]):
                return
        parsed=urlsplit(download)
        if (parsed.scheme!="https" or parsed.hostname!="github.com"
                or not parsed.path.startswith(
                  "/ricardoaldape/POTV/releases/download/")):
            print("POTV OTA: release URL not approved",flush=True)
            return
        version=str(release.get("version",version_code))[:60]
        notes=str(release.get("changelog",""))[:1600]
        message=("📦 POTV | Nueva actualización disponible\n\n"
                 "Versión: "+version+"\n\nCambios:\n"+notes+
                 "\n\nDescarga desde nuestro GitHub oficial.")
        tg("sendMessage",{"chat_id":GROUP_CHAT_ID,"text":message,
            "reply_markup":json.dumps({"inline_keyboard":[[
                {"text":"Descargar actualización","url":download},
                {"text":"Asistencia","url":"https://t.me/potvoficialbot"}]]})})
        with dbc() as c:
            c.execute("""UPDATE bot_runtime SET value=?
                         WHERE key='last_ota_version_code'""",
                      (str(version_code),))
        print("POTV OTA announced:",version,flush=True)
    except Exception as exc:
        print("POTV OTA notification check failed:",
              type(exc).__name__,flush=True)

def main():
    init_db()
    if "--self-test" in sys.argv:
        return self_test()
    threading.Thread(target=run_api,daemon=True).start()
    if not TOKEN:
        print(f"POTV API-only {HOST}:{PORT}; falta POTV_BOT_TOKEN",flush=True)
        while True:
            time.sleep(3600)

    me=tg("getMe").get("result",{})
    print(f"Telegram verified: @{me.get('username')} id={me.get('id')}",flush=True)
    if str(me.get("id"))!=str(BOT_ID):
        raise RuntimeError(f"Bot ID inesperado: {me.get('id')}")
    tg("setMyCommands",{"commands":json.dumps(BOT_COMMANDS,ensure_ascii=False)})
    from group_config import GROUP_CHAT_ID
    try:
        group=tg("getChat",{"chat_id":GROUP_CHAT_ID}).get("result",{})
        member=tg("getChatMember",{"chat_id":GROUP_CHAT_ID,
                   "user_id":BOT_ID}).get("result",{})
        print("POTV group:",group.get("id"),group.get("type"),
              "membership:",member.get("status"),flush=True)
    except Exception as exc:
        print("POTV group check failed:",type(exc).__name__,
              str(exc)[:120],flush=True)

    # One-time move announcement: publish only on first successful send.
    with dbc() as c:
        c.execute("""CREATE TABLE IF NOT EXISTS bot_runtime
                  (key TEXT PRIMARY KEY, value TEXT NOT NULL)""")
        prior=c.execute("""SELECT value FROM bot_runtime
                  WHERE key='group_welcome_20261011'""").fetchone()
    if not prior:
        try:
            welcome=("🏴‍☠️ POTV | Grupo oficial\n\n"
                     "Desde ahora las novedades, actualizaciones y anuncios "
                     "de POTV se compartirán en este grupo.\n\n"
                     "🛒 Suscripciones y renovaciones\n"
                     "🆘 Asistencia privada\n"
                     "🔗 Vinculación de la aplicación\n\n"
                     "Para cualquiera de estas gestiones abre nuestro bot. "
                     "No publiques comprobantes ni datos personales aquí.")
            tg("sendMessage",{"chat_id":GROUP_CHAT_ID,"text":welcome,
               "reply_markup":json.dumps({"inline_keyboard":[[
                   {"text":"Abrir POTV Bot",
                    "url":"https://t.me/potvoficialbot?start=comprar"}]]})})
            with dbc() as c:
                c.execute("INSERT OR IGNORE INTO bot_runtime VALUES(?,?)",
                          ("group_welcome_20261011",iso(now())))
            print("POTV inaugural community announcement delivered",flush=True)
        except Exception as exc:
            print("POTV inaugural message failed:",
                  type(exc).__name__,str(exc)[:100],flush=True)

    announce_new_version()
    last_ota_check=time.monotonic()
    offset=0
    print(f"POTV @{BOT_USER} + API {HOST}:{PORT}",flush=True)
    while True:
        try:
            # New account alerts are drained privately from the committed
            # outbox; the HTTP registration endpoint stays nonblocking.
            try:
                deliver_registration_notifications()
            except Exception as exc:
                print("POTV account notification worker:",type(exc).__name__,
                      flush=True)
            if time.monotonic()-last_ota_check>=300:
                announce_new_version()
                last_ota_check=time.monotonic()
            result=tg("getUpdates",{
                "timeout":30,
                "offset":offset,
                "allowed_updates":json.dumps(["message","callback_query"])
            })
            for upd in result.get("result",[]):
                offset=upd["update_id"]+1
                if upd.get("message"):
                    handle_message(upd["message"])
                elif upd.get("callback_query"):
                    handle_callback(upd["callback_query"])
        except KeyboardInterrupt:
            return 0
        except Exception as exc:
            print("poll error:",exc,file=sys.stderr)
            time.sleep(3)

if __name__=="__main__":
    raise SystemExit(main())