"""Private proof intake and human-only payment review for POTV."""
import json
import re
import secrets
from datetime import datetime, timedelta, timezone
from decimal import Decimal, InvalidOperation
from urllib.request import Request, urlopen
from urllib.parse import urlsplit
from zoneinfo import ZoneInfo

MEXICO = ZoneInfo("America/Mexico_City")
OFFICIAL_RELEASES = "https://github.com/ricardoaldape/POTV/releases"
EMAIL = re.compile(r"^[^\s@|]+@[^\s@|]+\.[^\s@|]+$")

def latest_apk():
    """Consult published GitHub releases for the newest APK on each request.

    No stale fixed APK: if GitHub is unreachable or the latest published
    release contains no APK, the button directs to the official releases page.
    """
    url = "https://api.github.com/repos/ricardoaldape/POTV/releases?per_page=30"
    try:
        req = Request(url, headers={"User-Agent": "POTV-telegram-bot", "Accept": "application/vnd.github+json"})
        with urlopen(req, timeout=8) as response:
            releases = json.load(response)
        published = [r for r in releases if r.get("published_at") and not r.get("draft")]
        if not published:
            return None, OFFICIAL_RELEASES
        release = max(published, key=lambda r: r["published_at"])
        for asset in release.get("assets", []):
            link = str(asset.get("browser_download_url") or "")
            parsed = urlsplit(link)
            if (parsed.scheme == "https" and parsed.hostname == "github.com"
                    and parsed.path.startswith("/ricardoaldape/POTV/releases/download/")
                    and parsed.path.lower().endswith(".apk")
                    and asset.get("size", 0) > 1000000):
                return str(release.get("tag_name", "POTV")), link
    except Exception as exc:
        print("POTV APK release lookup error:", type(exc).__name__, flush=True)
    return None, OFFICIAL_RELEASES

class PaymentOps:
    def __init__(self, g, send, alert_admin, get_flow, set_flow):
        self.g = g
        self.send = send
        self.alert_admin = alert_admin
        self.get_flow = get_flow
        self.set_flow = set_flow
        with g["dbc"]() as db:
            db.executescript("""
            CREATE TABLE IF NOT EXISTS bot_payment_drafts (
                telegram_id INTEGER PRIMARY KEY,
                email TEXT NOT NULL,
                amount_mxn TEXT NOT NULL,
                paid_at TEXT NOT NULL,
                bank_reference TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS bot_payment_details (
                payment_id INTEGER PRIMARY KEY,
                email TEXT, amount_mxn TEXT, paid_at TEXT,
                bank_reference TEXT, proof_type TEXT,
                proof_unique_id TEXT, reviewer_telegram_id INTEGER
            );
            CREATE INDEX IF NOT EXISTS idx_bot_payment_ref
                ON bot_payment_details(bank_reference,paid_at);
            """)

    def start(self, tid, cid):
        self.set_flow(tid, "payment_info")
        self.send(cid, "📤 Enviar comprobante POTV\n\n"
             "1️⃣ Escribe únicamente el CORREO con el que registraste tu cuenta POTV.\n"
             "2️⃣ Después, envía una foto o PDF del ticket de depósito.\n\n"
             "No necesitas escribir importe, fecha, hora ni referencia: "
             "nuestro equipo revisará esos datos en tu comprobante y "
             "confirmará el depósito antes de activar tu servicio.\n\n"
             "🔒 El comprobante se recibe de forma privada. "
             "Enviar el recibo NO activa automáticamente el servicio.\n"
             "Para salir: /cancelar", True)

    def _account(self, email, tid):
        account = self.g["ACCOUNT_STORE"].account_by_email(email)
        if not account:
            raise ValueError("El correo todavía no está registrado en la aplicación.")
        linked = account.get("telegram_chat_id")
        if linked and str(linked) != str(tid):
            raise ValueError("Ese correo está vinculado a otra cuenta de Telegram. Contacta a soporte.")
        return account

    def details(self, tid, cid, content):
        email = content.strip().lower()
        if not EMAIL.fullmatch(email) or len(email) > 254:
            self.send(cid, "⚠️ Escribe solo el correo de tu cuenta POTV.\n"
                      "Ejemplo: cliente@correo.com\n"
                      "No incluyas importes, fechas ni referencias bancarias.", True)
            return
        try:
            self._account(email, tid)
        except ValueError as exc:
            self.send(cid, "⚠️ " + str(exc), True)
            return
        with self.g["dbc"]() as db:
            # Preserve the existing schema for outstanding historic drafts.
            # Receipt details are verified by the operator, not self-reported.
            db.execute("""INSERT INTO bot_payment_drafts VALUES(?,?,?,?,?)
                ON CONFLICT(telegram_id) DO UPDATE SET
                email=excluded.email,amount_mxn=excluded.amount_mxn,
                paid_at=excluded.paid_at,bank_reference=excluded.bank_reference""",
                (tid,email,"","",""))
        self.set_flow(tid, "payment_receipt")
        self.send(cid, "✅ Correo registrado: " + email +
                  "\n\n📎 Ahora envía la foto o el PDF de tu comprobante de pago.\n"
                  "Lo revisará una persona y recibirás la respuesta aquí.\n"
                  "/cancelar para salir.", True)

    def receipt(self, tid, cid, message):
        if self.get_flow(tid) != "payment_receipt":
            self.send(cid, "Para informar un pago, selecciona primero «💳 Reportar pago».", True)
            return
        images = message.get("photo") or []
        document = message.get("document") or {}
        if images:
            attachment, typ = images[-1], "photo"
        elif document and document.get("mime_type") in ("application/pdf","image/jpeg","image/png","image/webp"):
            attachment, typ = document, "document"
        else:
            self.send(cid, "Adjunta una foto, JPG, PNG o PDF del comprobante.", True)
            return
        if int(attachment.get("file_size") or 0) > 15 * 1024 * 1024:
            self.send(cid, "Archivo demasiado grande (máximo 15 MB).", True)
            return
        file_id = attachment.get("file_id")
        unique = attachment.get("file_unique_id") or ""
        if not file_id:
            self.send(cid, "No pude leer el comprobante. Intenta adjuntarlo otra vez.", True)
            return
        with self.g["dbc"]() as db:
            draft = db.execute("SELECT * FROM bot_payment_drafts WHERE telegram_id=?", (tid,)).fetchone()
            if not draft:
                self.send(cid, "Faltan los datos del pago. Usa «💳 Reportar pago».", True)
                return
            if unique:
                previous = db.execute("""SELECT payment_id FROM bot_payment_details
                    WHERE proof_unique_id=? LIMIT 1""", (unique,)).fetchone()
                if previous:
                    self.send(cid, "Ese comprobante ya fue enviado como solicitud #"+
                              str(previous["payment_id"])+". Espera su revisión.", True)
                    self.set_flow(tid)
                    return
            ref = "POTV-" + secrets.token_hex(4).upper()
            cur = db.execute("""INSERT INTO payments
               (telegram_id,reference,photo_file_id,status,created_at)
               VALUES(?,?,?,'pending',?)""",
               (tid,ref,file_id,self.g["iso"](self.g["now"]())))
            payment_id = cur.lastrowid
            db.execute("""INSERT INTO bot_payment_details
                (payment_id,email,amount_mxn,paid_at,bank_reference,proof_type,proof_unique_id)
                VALUES(?,?,?,?,?,?,?)""",
                (payment_id,draft["email"],draft["amount_mxn"],draft["paid_at"],
                 draft["bank_reference"],typ,unique))
            db.execute("DELETE FROM bot_payment_drafts WHERE telegram_id=?", (tid,))
        self.set_flow(tid)
        self.send(cid, "✅ Comprobante recibido. Folio #"+str(payment_id)+
                  "\nEstado: PENDIENTE de validación humana.\n"
                  "Revisaremos el depósito bancario antes de activar el mes de POTV.", True)
        if callable(getattr(self,"on_receipt",None)):
            self.on_receipt(payment_id)
        else:
            self.alert_admin("💳 POTV: comprobante pendiente #"+str(payment_id)+
                             "\nRevisar: /verpago "+str(payment_id))

    def view(self, cid, pid):
        with self.g["dbc"]() as db:
            row = db.execute("""SELECT p.*,d.email,d.amount_mxn,d.paid_at,
                d.bank_reference,d.proof_type,d.reviewer_telegram_id
                FROM payments p LEFT JOIN bot_payment_details d ON d.payment_id=p.id
                WHERE p.id=?""", (pid,)).fetchone()
        if not row:
            self.send(cid, "Folio no encontrado.");return None
        info = ("💳 Comprobante #"+str(pid)+" | "+str(row["status"])+
                "\nTelegram: "+str(row["telegram_id"])+
                "\nCorreo POTV: "+str(row["email"] or "No capturado")+
                "\nImporte: "+(("$"+str(row["amount_mxn"])+" MXN") if row["amount_mxn"] else "Revisar en ticket")+
                "\nFecha/hora: "+str(row["paid_at"] or "Revisar en ticket")+
                "\nReferencia: "+str(row["bank_reference"] or "Revisar en ticket")+
                "\n\n⚠️ Verifica que el depósito REAL llegó a tu banco antes de aprobar.\n"
                "Aprobar: /approve "+str(pid)+" | Rechazar: /reject "+str(pid))
        method = "sendDocument" if row["proof_type"] == "document" else "sendPhoto"
        field = "document" if method == "sendDocument" else "photo"
        try:
            self.g["tg"](method, {"chat_id":cid,field:row["photo_file_id"],"caption":info[:1024]})
        except Exception as exc:
            print("POTV payment attachment preview failed:",type(exc).__name__,flush=True)
            self.send(cid,info+"\nNo se pudo cargar la imagen; puedes consultar el folio.")
        return row

    def assign_email(self, cid, tid, pid, email):
        if not EMAIL.fullmatch(email):
            self.send(cid,"Correo inválido.");return
        with self.g["dbc"]() as db:
            r = db.execute("SELECT * FROM payments WHERE id=? AND status='pending'",(pid,)).fetchone()
            if not r:
                self.send(cid,"Folio no pendiente.");return
            try:
                self._account(email,int(r["telegram_id"]))
            except ValueError as exc:
                self.send(cid,str(exc));return
            db.execute("""INSERT INTO bot_payment_details(payment_id,email)
                VALUES(?,?) ON CONFLICT(payment_id) DO UPDATE SET email=excluded.email""",(pid,email.lower()))
        self.send(cid,"Correo asignado al pago #"+str(pid)+". Verifica banco y usa /approve "+str(pid))

    def decide(self, operator, cid, pid, approve):
        with self.g["dbc"]() as db:
            row = db.execute("""SELECT p.*,d.email,d.amount_mxn,d.bank_reference,d.paid_at
                 FROM payments p LEFT JOIN bot_payment_details d ON d.payment_id=p.id
                 WHERE p.id=? AND p.status='pending'""",(pid,)).fetchone()
            if not row:
                self.send(cid,"Folio no encontrado o ya revisado.");return
            # Only the registered email and actual receipt are required
            # from the customer. The operator checks amount, date, time,
            # reference and settlement directly in the bank before approving.
            if approve and not (row["email"] and row["photo_file_id"]):
                self.send(cid,"Falta el correo registrado o el comprobante de pago. "
                          "No es posible activar un folio incompleto.");return
            if approve:
                try:
                    account = self._account(row["email"],row["telegram_id"])
                except ValueError as exc:
                    self.send(cid,str(exc));return
                if row["bank_reference"]:
                    duplicate = db.execute("""SELECT p.id FROM payments p JOIN bot_payment_details d
                        ON d.payment_id=p.id WHERE p.status='approved'
                        AND d.bank_reference=? AND p.id<>? LIMIT 1""",
                        (row["bank_reference"],pid)).fetchone()
                    if duplicate:
                        self.send(cid,"Referencia ya aprobada en folio #"+str(duplicate["id"])+
                                  ". Revisa un posible comprobante duplicado.");return
            updated = db.execute("""UPDATE payments SET status='reviewing'
                WHERE id=? AND status='pending'""",(pid,)).rowcount
            if not updated:
                self.send(cid,"Folio ya tomado para revisión.");return
        if approve:
            try:
                result = self.g["ACCOUNT_STORE"].activate_manual(
                    row["email"],approved_by="telegram:"+str(operator),payment_confirmed=True,
                    payment_reference="potv-telegram-"+str(pid),
                    payment_paid_at=row["paid_at"] or None)
                expiry = result["subscription_expires_at"]
                with self.g["dbc"]() as db:
                    db.execute("""INSERT INTO subscriptions
                        (telegram_id,status,starts_at,expires_at,updated_at)
                        VALUES(?,'active',?,?,?)
                        ON CONFLICT(telegram_id) DO UPDATE SET
                        status='active',expires_at=excluded.expires_at,
                        updated_at=excluded.updated_at""",
                        (row["telegram_id"],self.g["iso"](self.g["now"]()),
                         expiry,self.g["iso"](self.g["now"]())))
            except Exception as exc:
                with self.g["dbc"]() as db:
                    db.execute("UPDATE payments SET status='pending' WHERE id=? AND status='reviewing'",(pid,))
                print("POTV manual payment approval failed:",type(exc).__name__,flush=True)
                self.send(cid,"No se activó; sigue pendiente. Revisa el correo y la cuenta.");return
            status = "approved"
        else:
            expiry = None
            status = "rejected"
        with self.g["dbc"]() as db:
            db.execute("""UPDATE payments SET status=?,reviewed_at=?
                WHERE id=? AND status='reviewing'""",(status,self.g["iso"](self.g["now"]()),pid))
            db.execute("UPDATE bot_payment_details SET reviewer_telegram_id=? WHERE payment_id=?",
                       (operator,pid))
        self.send(cid,"Pago #"+str(pid)+(" aprobado hasta "+str(expiry) if approve else " rechazado."))
        try:
            self.send(row["telegram_id"],
                      ("✅ Pago validado por POTV. Tu suscripción vence: "+str(expiry)
                       if approve else "❌ No pudimos validar tu depósito. Contacta a soporte."),
                      True)
        except Exception:
            pass
