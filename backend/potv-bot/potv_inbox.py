"""POTV private operator inbox: ticket routing, proof previews, payment guide."""
import json

class OperatorInbox:
    def __init__(self, g, send, is_admin, admin_targets, set_flow):
        self.g = g
        self.tg, self.dbc = g["tg"], g["dbc"]
        self.send, self.is_admin = send, is_admin
        self.admin_targets, self.set_flow = admin_targets, set_flow
        with self.dbc() as db:
            db.executescript("""
                CREATE TABLE IF NOT EXISTS bot_operator_messages(
                    operator_id INTEGER NOT NULL,
                    message_id INTEGER NOT NULL,
                    subject_type TEXT NOT NULL,
                    subject_id INTEGER NOT NULL,
                    created_at TEXT NOT NULL,
                    PRIMARY KEY(operator_id,message_id));
                CREATE TABLE IF NOT EXISTS bot_media_settings(
                    name TEXT PRIMARY KEY, file_id TEXT NOT NULL,
                    media_type TEXT NOT NULL DEFAULT 'photo',
                    updated_at TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS support_ticket_replies(
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    ticket_id INTEGER NOT NULL,
                    operator_id INTEGER NOT NULL,
                    message TEXT NOT NULL,
                    created_at TEXT NOT NULL);
            """)
            fields={item["name"] for item in db.execute("PRAGMA table_info(bot_media_settings)")}
            if "media_type" not in fields:
                db.execute("ALTER TABLE bot_media_settings ADD COLUMN media_type TEXT NOT NULL DEFAULT 'photo'")

    def _record(self, target, result, kind, subject_id):
        mid = (result or {}).get("result", {}).get("message_id")
        if mid:
            with self.dbc() as db:
                db.execute("""INSERT OR REPLACE INTO bot_operator_messages
                    (operator_id,message_id,subject_type,subject_id,created_at)
                    VALUES(?,?,?,?,?)""",
                    (int(target),int(mid),kind,int(subject_id),
                     self.g["iso"](self.g["now"]())))

    def _name(self, tid):
        with self.dbc() as db:
            row=db.execute("SELECT first_name,username FROM users WHERE telegram_id=?",
                           (int(tid),)).fetchone()
            acct=db.execute("SELECT email FROM app_accounts WHERE telegram_id=?",
                            (int(tid),)).fetchone()
        name=((row["first_name"] or row["username"]) if row else "") or "Cliente"
        handle=("@"+row["username"]) if row and row["username"] else ""
        email=acct["email"] if acct else "Correo no vinculado"
        return name[:80],handle[:100],email[:254]

    def notify_ticket(self, tid, ticket_id, issue):
        name,handle,email = self._name(tid)
        msg=("🆘 NUEVO TICKET POTV #"+str(ticket_id)+
             "\nCliente: "+name+(" "+handle if handle else "")+
             "\nCorreo: "+email+"\nTelegram ID: "+str(tid)+
             "\n\nMensaje:\n"+str(issue)[:2400]+
             "\n\nResponde DIRECTAMENTE a este mensaje para contestar al cliente. "
             "También puedes usar /reply "+str(ticket_id)+" texto.")
        kb={"inline_keyboard":[
            [{"text":"✍️ Responder","callback_data":"ticket:reply:"+str(ticket_id)},
             {"text":"✅ Cerrar ticket","callback_data":"ticket:close:"+str(ticket_id)}]]}
        for target in self.admin_targets():
            if not self.is_admin(target):
                continue
            try:
                result=self.tg("sendMessage",{"chat_id":target,"text":msg,
                             "reply_markup":json.dumps(kb,ensure_ascii=False)})
                self._record(target,result,"ticket",ticket_id)
            except Exception as exc:
                print("POTV ticket DM delivery failed:",type(exc).__name__,flush=True)

    def notify_payment(self, payment_id):
        with self.dbc() as db:
            row=db.execute("""SELECT p.*,d.email,d.amount_mxn,d.paid_at,
                d.bank_reference,d.proof_type
                FROM payments p LEFT JOIN bot_payment_details d ON d.payment_id=p.id
                WHERE p.id=?""",(int(payment_id),)).fetchone()
        if not row: return
        name,handle,email=self._name(row["telegram_id"])
        msg=("💳 COMPROBANTE PENDIENTE #"+str(payment_id)+
             "\nCliente: "+name+(" "+handle if handle else "")+
             "\nCorreo POTV: "+str(row["email"] or email)+
             "\nImporte: "+(("$"+str(row["amount_mxn"])+" MXN") if row["amount_mxn"] else "Revisar ticket")+
             "\nFecha/hora: "+str(row["paid_at"] or "Revisar ticket")+
             "\nReferencia: "+str(row["bank_reference"] or "Revisar ticket")+
             "\nTelegram ID: "+str(row["telegram_id"])+
             "\n\n⚠️ Verifica el dinero en el banco antes de aprobar.")
        kb={"inline_keyboard":[
            [{"text":"✅ Revisado: activar","callback_data":"payment:confirm:"+str(payment_id)},
             {"text":"❌ Rechazar","callback_data":"payment:reject:"+str(payment_id)}],
            [{"text":"🔎 Ver comprobante","callback_data":"payment:view:"+str(payment_id)}]]}
        method="sendDocument" if row["proof_type"]=="document" else "sendPhoto"
        field="document" if method=="sendDocument" else "photo"
        for target in self.admin_targets():
            if not self.is_admin(target):
                continue
            try:
                payload={"chat_id":target,field:row["photo_file_id"],
                         "caption":msg[:1024],
                         "reply_markup":json.dumps(kb,ensure_ascii=False)}
                result=self.tg(method,payload)
                self._record(target,result,"payment",payment_id)
            except Exception as exc:
                print("POTV receipt DM failed:",type(exc).__name__,flush=True)
                try:
                    result=self.send(target,msg+
                                     "\nVer imagen: /verpago "+str(payment_id))
                    self._record(target,result,"payment",payment_id)
                except Exception:
                    pass

    def configure_guide(self, operator, message):
        if not self.is_admin(operator):
            return False
        pics=message.get("photo") or []
        doc=message.get("document") or {}
        if pics: chosen=pics[-1]; typ="photo"
        elif doc and doc.get("mime_type") in ("image/jpeg","image/png","image/webp"):
            chosen=doc; typ="document"
        else:
            self.send(operator,"Envía la imagen OXXO como foto o JPG/PNG. /cancelar para salir.")
            return False
        if not chosen.get("file_id"):
            self.send(operator,"No llegó una imagen válida.")
            return False
        if int(chosen.get("file_size") or 0)>10_000_000:
            self.send(operator,"Imagen demasiado grande, envía una menor a 10 MB.")
            return False
        file_id=chosen["file_id"]
        with self.dbc() as db:
            db.execute("""INSERT INTO bot_media_settings(name,file_id,media_type,updated_at)
                VALUES('payment_guide',?,?,?)
                ON CONFLICT(name) DO UPDATE SET file_id=excluded.file_id,
                media_type=excluded.media_type,updated_at=excluded.updated_at""",
                (file_id,typ,self.g["iso"](self.g["now"]())))
        self.set_flow(operator)
        self.send(operator,"✅ Imagen de medios de pago guardada. "
                  "Se mostrará a todos los clientes al entrar a 💳 Medios de pago.",True)
        return True

    def send_guide(self, cid):
        with self.dbc() as db:
            row=db.execute("SELECT file_id,media_type FROM bot_media_settings WHERE name='payment_guide'").fetchone()
        if not row:
            return False
        try:
            media_type="document" if row["media_type"]=="document" else "photo"
            method="sendDocument" if media_type=="document" else "sendPhoto"
            self.tg(method,{"chat_id":cid,media_type:row["file_id"],
                     "caption":"🏴‍☠️ POTV | Medios de pago\n"
                     "Guarda tu comprobante y envíalo por este chat con el correo de tu cuenta. "
                     "La activación requiere verificación humana."})
            return True
        except Exception as exc:
            print("POTV guide photo error:",type(exc).__name__,flush=True)
            return False

    def reply_to_message(self, operator, original_message_id, answer):
        with self.dbc() as db:
            row=db.execute("""SELECT subject_type,subject_id
                FROM bot_operator_messages WHERE operator_id=? AND message_id=?""",
                (int(operator),int(original_message_id))).fetchone()
        if not row:
            return False
        if row["subject_type"]!="ticket":
            self.send(operator,"Para los comprobantes utiliza /verpago ID, "
                      "/approve ID o /reject ID. Nunca se aprueba por respuesta de texto.")
            return True
        ticket=int(row["subject_id"])
        with self.dbc() as db:
            record=db.execute("""SELECT * FROM support_tickets WHERE id=? AND status='open'""",
                              (ticket,)).fetchone()
        if not record:
            self.send(operator,"Este ticket ya está cerrado o no existe.")
            return True
        self.tg("sendMessage",{"chat_id":record["telegram_id"],
                 "text":"🆘 Soporte POTV | Ticket #"+str(ticket)+"\n\n"+answer[:3000]})
        with self.dbc() as db:
            stamp=self.g["iso"](self.g["now"]())
            db.execute("UPDATE support_tickets SET updated_at=? WHERE id=?",(stamp,ticket))
            db.execute("""INSERT INTO support_ticket_replies(ticket_id,operator_id,message,created_at)
                VALUES(?,?,?,?)""",(ticket,operator,answer[:3000],stamp))
        self.send(operator,"✅ Respuesta entregada al cliente del ticket #"+str(ticket))
        return True
