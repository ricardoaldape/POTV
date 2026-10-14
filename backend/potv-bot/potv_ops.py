"""POTV community, support, and sales operations; SQLite-compatible extension."""
import json
import secrets
from group_config import GROUP_CHAT_ID, GROUP_INVITE_URL, BOT_PUBLIC_URL

def install(g):
    old = g['handle_message']
    tg, dbc = g['tg'], g['dbc']
    admin = str(g['ADMIN'] or '')
    now, iso = g['now'], g['iso']
    bot_name = g['BOT_USER']
    kb = json.dumps({"keyboard": [
        ["🛒 Comprar", "📺 Planes"],
        ["👤 Mi cuenta", "💳 Reportar pago"],
        ["🔗 Vincular app", "🆘 Soporte"],
        ["👥 Grupo", "❓ Ayuda"]], "resize_keyboard": True},
        ensure_ascii=False)

    with dbc() as c:
        c.executescript("""
        CREATE TABLE IF NOT EXISTS bot_sessions (
          telegram_id INTEGER PRIMARY KEY, flow TEXT, updated_at TEXT);
        CREATE TABLE IF NOT EXISTS support_tickets (
          id INTEGER PRIMARY KEY AUTOINCREMENT, telegram_id INTEGER NOT NULL,
          message TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'open',
          created_at TEXT NOT NULL, updated_at TEXT NOT NULL);
        CREATE INDEX IF NOT EXISTS idx_tickets_status
          ON support_tickets(status,id);
        CREATE TABLE IF NOT EXISTS bot_operators (
          telegram_id INTEGER PRIMARY KEY, role TEXT NOT NULL,
          created_at TEXT NOT NULL);
        """)

    def send(cid, body, menu=False, links=None):
        payload = {"chat_id": cid, "text": body[:3900],
                   "disable_web_page_preview": "true"}
        if links:
            payload["reply_markup"] = json.dumps({"inline_keyboard": [
                [{"text": label, "url": url}] for label, url in links]})
        elif menu:
            payload["reply_markup"] = kb
        return tg("sendMessage", payload)

    def flow(tid):
        with dbc() as c:
            r = c.execute("SELECT flow FROM bot_sessions WHERE telegram_id=?",
                          (tid,)).fetchone()
        return r["flow"] if r else None

    def set_flow(tid, value=None):
        with dbc() as c:
            if value:
                c.execute("""INSERT INTO bot_sessions VALUES(?,?,?)
                ON CONFLICT(telegram_id) DO UPDATE SET
                flow=excluded.flow,updated_at=excluded.updated_at""",
                (tid,value,iso(now())))
            else:
                c.execute("DELETE FROM bot_sessions WHERE telegram_id=?", (tid,))

    def is_admin(tid):
        if admin and str(tid)==admin:
            return True
        with dbc() as c:
            r=c.execute("SELECT role FROM bot_operators WHERE telegram_id=?",
                        (tid,)).fetchone()
        if not r or r["role"]!="owner":
            return False
        # Revoked ownership must immediately revoke administrative powers.
        try:
            current=tg("getChatMember",
                       {"chat_id":GROUP_CHAT_ID,"user_id":tid}).get("result",{})
            return current.get("status")=="creator"
        except Exception:
            return False

    def admin_targets():
        with dbc() as c:
            rows=c.execute("SELECT telegram_id FROM bot_operators").fetchall()
        targets={int(r["telegram_id"]) for r in rows}
        if admin and admin.isdigit():
            targets.add(int(admin))
        return targets

    def alert_admin(text):
        for target in admin_targets():
            if not is_admin(target):
                continue
            try: send(target,text)
            except Exception as e:
                print("POTV admin alert failed:",type(e).__name__,flush=True)

    def home(cid):
        send(cid,"🏴‍☠️ POTV | Asistencia y suscripciones\n\n"
             "Aquí puedes comprar, renovar, consultar tu cuenta, "
             "vincular tu aplicación y contactar a soporte.\n"
             "Nuestra comunidad está en «👥 Grupo».",True)

    def plans(cid):
        send(cid,"📺 Planes POTV\n\n"+g['PLAN_TEXT']+
             "\n\nPulsa «🛒 Comprar» para continuar.",True)

    def buy(cid):
        with dbc() as c:
            row=c.execute("""SELECT id FROM support_tickets
                WHERE telegram_id=? AND status='open'
                  AND message='Solicitud de compra POTV' LIMIT 1""",
                (cid,)).fetchone()
            if row:
                folio=row["id"]
            else:
                cur=c.execute("""INSERT INTO support_tickets
                    (telegram_id,message,created_at,updated_at)
                    VALUES(?,?,?,?)""",
                    (cid,"Solicitud de compra POTV",iso(now()),iso(now())))
                folio=cur.lastrowid
        if not row:
            alert_admin("🛒 Solicitud de compra #"+str(folio)+
                        "\nUsuario: "+str(cid)+"\nVer: /ver "+str(folio))
        send(cid,"🛒 Compra o renovación POTV\n\n"+g['PLAN_TEXT']+
             "\n\n✅ Solicitud registrada #"+str(folio)+
             ". Te atenderemos por este chat.\n"
             "Si ya realizaste tu pago, selecciona «💳 Reportar pago».",
             True)

    def help_message(cid):
        send(cid,"❓ POTV | Ayuda rápida\n"
             "🛒 Comprar y 📺 Planes: suscripciones.\n"
             "👤 Mi cuenta: estado y vencimiento.\n"
             "💳 Reportar pago: comprobante privado.\n"
             "🔗 Vincular app: código válido 10 minutos.\n"
             "🆘 Soporte: ticket de ayuda.\n"
             "👥 Grupo: comunidad y anuncios.\n"
             "/cancelar: cancelar operación.",True)

    def add_ticket(tid,cid,message):
        with dbc() as c:
            cur=c.execute("""INSERT INTO support_tickets
              (telegram_id,message,created_at,updated_at)
              VALUES(?,?,?,?)""",(tid,message[:2500],iso(now()),iso(now())))
            ticket=cur.lastrowid
        set_flow(tid)
        send(cid,"✅ Ticket de soporte #"+str(ticket)+
             " registrado. Te responderemos por aquí.",True)
        alert_admin("🆘 POTV nuevo ticket #"+str(ticket)+
                    "\nUsuario: "+str(tid)+"\nVer: /ver "+str(ticket))

    def admin_command(tid,cid,text):
        if not is_admin(tid):
            send(cid,"Comando reservado a administración.")
            return
        bits=text.split(maxsplit=2)
        cmd=bits[0].split('@')[0].lower()
        if cmd=='/pending':
            with dbc() as c:
                rows=c.execute("""SELECT id,telegram_id,reference FROM payments
                    WHERE status='pending' ORDER BY id LIMIT 25""").fetchall()
            report="\n".join("#"+str(r["id"])+" | "+str(r["telegram_id"])+
                             " | "+r["reference"] for r in rows)
            send(cid,"💳 Pagos pendientes:\n"+(report or "Ninguno."))
            return
        if cmd in ('/approve','/reject'):
            if len(bits)<2 or not bits[1].isdigit():
                send(cid,"Uso: "+cmd+" ID"+
                     (" [días]" if cmd=='/approve' else ""));return
            payment_id=int(bits[1])
            with dbc() as c:
                r=c.execute("""SELECT * FROM payments
                    WHERE id=? AND status='pending'""",(payment_id,)).fetchone()
            if not r:
                send(cid,"Pago no encontrado o ya revisado.");return
            if cmd=='/approve':
                if len(bits)==3 and (not bits[2].isdigit() or
                                    not 1<=int(bits[2])<=365):
                    send(cid,"Los días deben estar entre 1 y 365.");return
                days=int(bits[2]) if len(bits)==3 else 30
                try:
                    expiry=g['activate'](int(r["telegram_id"]),days)
                except Exception as exc:
                    print("POTV activation failed:",type(exc).__name__,flush=True)
                    send(cid,"Error de activación; pago sigue pendiente.")
                    return
                new_status='approved'
            else:
                expiry=None
                new_status='rejected'
            with dbc() as c:
                result=c.execute("""UPDATE payments
                    SET status=?,reviewed_at=?
                    WHERE id=? AND status='pending'""",
                    (new_status,iso(now()),payment_id))
            if not result.rowcount:
                send(cid,"Pago ya revisado.");return
            send(cid,"Pago #"+str(payment_id)+" "+new_status+
                 (" hasta "+iso(expiry) if expiry else ""))
            try:
                if expiry:
                    send(r["telegram_id"],"✅ Suscripción POTV activa.\n"+
                         "Vence: "+iso(expiry),True)
                else:
                    send(r["telegram_id"],"No se validó tu comprobante. "+
                         "Contacta a soporte para revisarlo.",True)
            except Exception:
                pass
            return
        if cmd=='/tickets':
            with dbc() as c:
                rows=c.execute("""SELECT id,telegram_id FROM support_tickets
                    WHERE status='open' ORDER BY id LIMIT 25""").fetchall()
            report="\n".join("#"+str(r["id"])+" | "+str(r["telegram_id"])
                             for r in rows) or "No hay tickets abiertos."
            send(cid,"🆘 Soporte pendiente:\n"+report+
                 "\n\n/ver ID, /reply ID texto, /close ID")
        elif cmd=='/ver':
            if len(bits)<2 or not bits[1].isdigit():
                send(cid,"Uso: /ver ID"); return
            with dbc() as c:
                r=c.execute("SELECT * FROM support_tickets WHERE id=?",
                            (int(bits[1]),)).fetchone()
            if not r:
                send(cid,"Ticket no encontrado.");return
            send(cid,"🆘 Ticket #"+str(r["id"])+" ("+r["status"]+")\n"+
                 "Usuario: "+str(r["telegram_id"])+"\n"+r["message"])
        elif cmd=='/reply':
            if len(bits)<3 or not bits[1].isdigit() or not bits[2].strip():
                send(cid,"Uso: /reply ID mensaje");return
            with dbc() as c:
                r=c.execute("""SELECT * FROM support_tickets
                   WHERE id=? AND status='open'""",(int(bits[1]),)).fetchone()
            if not r:
                send(cid,"Ticket cerrado o inexistente.");return
            try:
                send(r["telegram_id"],"🆘 Soporte POTV | Ticket #"+
                     bits[1]+"\n\n"+bits[2],True)
            except Exception:
                send(cid,"El usuario no pudo recibir la respuesta.");return
            with dbc() as c:
                c.execute("UPDATE support_tickets SET updated_at=? WHERE id=?",
                          (iso(now()),int(bits[1])))
            send(cid,"✅ Respuesta enviada.")
        elif cmd=='/close':
            if len(bits)<2 or not bits[1].isdigit():
                send(cid,"Uso: /close ID");return
            with dbc() as c:
                res=c.execute("""UPDATE support_tickets SET status='closed',
                   updated_at=? WHERE id=? AND status='open'""",
                   (iso(now()),int(bits[1])))
            send(cid,"Ticket cerrado." if res.rowcount else "No está abierto.")
        elif cmd=='/anuncio':
            message=text.partition(' ')[2].strip()
            if not message or len(message)>3500:
                send(cid,"Uso: /anuncio texto (máximo 3500 caracteres)")
                return
            try:
                result=send(GROUP_CHAT_ID,
                            "📣 POTV | Aviso oficial\n\n"+message,
                            links=[("Asistencia y suscripciones",
                                    BOT_PUBLIC_URL+"?start=comprar")])
                mid=result.get('result',{}).get('message_id','?')
                send(cid,"✅ Publicado en el grupo. Mensaje #"+str(mid))
            except Exception as e:
                print("POTV group publish failed:",
                      type(e).__name__,flush=True)
                send(cid,"No pude publicar. Comprueba que el bot "
                     "sea miembro del grupo y tenga permiso para escribir.")

    def handle(message):
        chat=message.get('chat') or {}
        cid=chat.get('id')
        typ=chat.get('type')
        text=(message.get('text') or '').strip()
        cmd=text.split(' ',1)[0].split('@')[0].lower()
        if typ!='private':
            if str(cid)==GROUP_CHAT_ID:
                if message.get('new_chat_members'):
                    joined=message['new_chat_members']
                    if any(str(u.get('id'))==str(g['BOT_ID']) for u in joined):
                        print("POTV added to official group",flush=True)
                    elif len(joined)<=4:
                        send(cid,"🏴‍☠️ ¡Bienvenidos a POTV! "
                             "Compras y soporte se atienden en privado.",
                             links=[("Abrir bot POTV",BOT_PUBLIC_URL)])
                elif cmd in ('/menu','/grupo','/ayuda','/start'):
                    send(cid,"Para compras, asistencia y vinculación "
                         "abre el bot en privado.",
                         links=[("Abrir bot POTV",BOT_PUBLIC_URL)])
            return
        user=message.get('from') or {}
        if not user.get('id') or user.get('is_bot'):
            return
        tid=int(user['id'])
        if cmd=='/id':
            send(cid,"Tu ID de Telegram: "+str(tid));return
        if cmd=='/activaradmin':
            try:
                member=tg("getChatMember",
                          {"chat_id":GROUP_CHAT_ID,"user_id":tid}
                          ).get("result",{})
                if member.get("status")!="creator":
                    send(cid,"Solo el propietario del grupo oficial "
                         "puede activar administración.");return
                with dbc() as c:
                    c.execute("""INSERT INTO bot_operators VALUES(?,?,?)
                      ON CONFLICT(telegram_id) DO UPDATE SET
                      role=excluded.role""",(tid,'owner',iso(now())))
                send(cid,"✅ Administración POTV activada.\n"
                     "Comandos: /pending, /approve, /reject, /tickets, "
                     "/ver, /reply, /close y /anuncio.",True)
            except Exception as exc:
                print("POTV admin claim failed:",
                      type(exc).__name__,flush=True)
                send(cid,"No se pudo verificar la titularidad del grupo. "
                     "Asegúrate de que el bot sea administrador del grupo.")
            return
        if cmd in ('/pending','/approve','/reject',
                   '/tickets','/ver','/reply','/close','/anuncio'):
            admin_command(tid,cid,text);return
        if cmd=='/cancelar':
            set_flow(tid)
            send(cid,"Operación cancelada.",True);return
        if cmd in ('/start','/menu'):
            if 'comprar' in text.lower(): buy(cid)
            else: home(cid)
            return
        if cmd=='/planes' or text=='📺 Planes':
            plans(cid);return
        if cmd=='/comprar' or text=='🛒 Comprar':
            buy(cid);return
        if cmd=='/grupo' or text=='👥 Grupo':
            send(cid,"👥 Comunidad oficial POTV\n"
                 "Anuncios, novedades y ayuda entre usuarios. "
                 "No compartas comprobantes ni datos privados en el grupo.",
                 links=[("Entrar al grupo oficial",GROUP_INVITE_URL)])
            return
        if cmd=='/ayuda' or text=='❓ Ayuda':
            help_message(cid);return
        if cmd=='/soporte' or text=='🆘 Soporte':
            set_flow(tid,'support')
            send(cid,"🆘 Soporte POTV\nDescribe tu problema, "
                 "dispositivo y versión de la app. "
                 "No envíes contraseñas ni datos bancarios.\n"
                 "Para cancelar: /cancelar",True)
            return
        if cmd=='/pago' or text=='💳 Reportar pago':
            set_flow(tid,'payment')
            send(cid,"💳 Pago o renovación\n\n"+g['PAYMENT_TEXT']+
                 "\n\nEnvía AQUÍ en privado una foto del comprobante. "
                 "Un administrador revisará tu solicitud antes de activarla.\n"
                 "Para cancelar: /cancelar",True)
            return
        if cmd=='/cuenta' or text=='👤 Mi cuenta':
            old(dict(message,text="👤 Mi cuenta"));return
        if cmd=='/vincular' or text=='🔗 Vincular app':
            old(dict(message,text="🔗 Vincular app"));return
        if message.get('photo'):
            if flow(tid)=='payment':
                old(message)
                set_flow(tid)
                with dbc() as c:
                    r=c.execute("""SELECT id FROM payments WHERE telegram_id=?
                       ORDER BY id DESC LIMIT 1""",(tid,)).fetchone()
                if r:
                    alert_admin("💳 Comprobante POTV #"+str(r['id'])+
                                "\nUsuario: "+str(tid)+"\nRevisar: /pending")
            else:
                send(cid,"Para enviar comprobantes, pulsa primero "
                     "«💳 Reportar pago». Para ayuda, pulsa «🆘 Soporte».",True)
            return
        if text and flow(tid)=='support':
            add_ticket(tid,cid,text);return
        if text and flow(tid)=='payment':
            send(cid,"Adjunta una fotografía del comprobante o "
                 "escribe /cancelar.",True);return
        home(cid)

    commands=[
        {"command":"start","description":"Abrir POTV"},
        {"command":"menu","description":"Menú principal"},
        {"command":"planes","description":"Ver planes"},
        {"command":"comprar","description":"Comprar o renovar"},
        {"command":"cuenta","description":"Estado de suscripción"},
        {"command":"pago","description":"Enviar comprobante"},
        {"command":"vincular","description":"Vincular POTV"},
        {"command":"soporte","description":"Solicitar asistencia"},
        {"command":"grupo","description":"Comunidad oficial"},
        {"command":"ayuda","description":"Guía de uso"},
        {"command":"id","description":"Mi ID de Telegram"},
        {"command":"activaradmin","description":"Administración (propietario)"}
    ]
    g['KB']=kb
    return handle,commands