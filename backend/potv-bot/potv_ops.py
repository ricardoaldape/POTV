"""POTV community, support, and sales operations; SQLite-compatible extension."""
import json
import secrets
from group_config import GROUP_CHAT_ID, GROUP_INVITE_URL, BOT_PUBLIC_URL
from potv_payments import PaymentOps, latest_apk
from potv_inbox import OperatorInbox
from potv_stats import report as private_stats_report, deliver as deliver_registration_events

def install(g):
    old = g['handle_message']
    tg, dbc = g['tg'], g['dbc']
    admin = str(g['ADMIN'] or '')
    now, iso = g['now'], g['iso']
    bot_name = g['BOT_USER']
    kb = json.dumps({"is_persistent": True, "one_time_keyboard": False, "keyboard": [
        ["📥 Descargar aplicación", "📺 Planes"],
        ["🛒 Comprar", "💳 Medios de pago"],
        ["📤 Enviar comprobante", "👤 Mi cuenta"],
        ["🔗 Vincular app", "🆘 Soporte"],
        ["🎫 Mis tickets", "👥 Grupo"],
        ["↩️ Menú principal", "❓ Ayuda"]], "resize_keyboard": True},
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
        elif menu or (isinstance(cid,int) and cid>0):
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

    def is_group_owner(tid):
        """Verify Telegram group ownership against the current supergroup.
        Telegram allows getChatAdministrators for member bots, whereas
        getChatMember of other users is not reliable without bot admin rights.
        """
        try:
            result=tg("getChatAdministrators",{"chat_id":GROUP_CHAT_ID})
            members=result.get("result") or []
            return any(
                m.get("status")=="creator" and
                str((m.get("user") or {}).get("id"))==str(tid)
                for m in members
            )
        except Exception as exc:
            print("POTV group owner verification failed:",
                  type(exc).__name__,flush=True)
            return False

    def is_admin(tid):
        if admin and str(tid)==admin:
            return True
        with dbc() as c:
            r=c.execute("SELECT role FROM bot_operators WHERE telegram_id=?",
                        (tid,)).fetchone()
        if not r or r["role"]!="owner":
            return False
        # Revocation of group ownership immediately disables bot admin access.
        return is_group_owner(tid)

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

    # The queue is drained from the bot's polling loop, never the HTTP
    # registration request. Only currently verified owners are recipients.
    g['deliver_registration_notifications'] = (
        lambda: deliver_registration_events(dbc,tg,admin_targets,is_admin)
    )

    payments = PaymentOps(g,send,alert_admin,flow,set_flow)
    inbox = OperatorInbox(g,send,is_admin,admin_targets,set_flow)
    payments.on_receipt = inbox.notify_payment

    def home(cid):
        send(cid,"🏴‍☠️ ¡Bienvenido a POTV!\n\n"
             "🎬 Películas, series, anime y deportes.\n\n"
             "Desde aquí puedes descargar POTV, consultar planes, pagar, renovar y pedir soporte.\n"
             "💳 Tus pagos siempre se validan manualmente. Te avisaremos al aprobarlos.\n\n"
             "👇 Elige una opción: el menú seguirá disponible.",True)

    def download(cid):
        version, link = latest_apk()
        if not version:
            send(cid,"📥 POTV\n\nNo pude comprobar cuál es la APK más reciente. "
                 "Para evitar versiones antiguas, abre las publicaciones oficiales de GitHub.",
                 links=[("Ver últimas versiones",link)])
            return
        send(cid,"📥 POTV para Android y Android TV\n\n"
             "Última APK publicada en GitHub: "+version+"\n"
             "Enlace consultado en tiempo real, sin versiones fijas.\n"
             "Después de instalar, registra tu correo en la app.\n\n"
             "Los primeros 5 días son de prueba; la suscripción posterior requiere pago validado.",
             links=[("📥 Descargar APK más reciente",link),
                    ("Ver todas las versiones","https://github.com/ricardoaldape/POTV/releases")])

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
             "\n\nTu solicitud de compra quedó registrada con el folio #"+str(folio)+
             ".\nConsulta «💳 Medios de pago» para depositar en OXXO.\n"
             "Cuando hayas pagado, pulsa «📤 Enviar comprobante»: "
             "únicamente necesitaremos tu correo y foto del ticket.",
             True)

    def help_message(cid):
        send(cid,"❓ POTV | Ayuda rápida\n"
             "🛒 Comprar y 📺 Planes: suscripciones.\n"
             "👤 Mi cuenta: estado y vencimiento.\n"
             "💳 Medios de pago: instrucciones de depósito OXXO.\n"
             "📤 Enviar comprobante: solo tu correo y la foto/PDF del ticket.\n"
             "📥 Descargar aplicación: APK oficial para Android y Android TV.\n"
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
        inbox.notify_ticket(tid,ticket,message[:2500])

    def admin_command(tid,cid,text):
        if not is_admin(tid):
            send(cid,"Comando reservado a administración.")
            return
        bits=text.split(maxsplit=2)
        cmd=bits[0].split('@')[0].lower()
        if cmd in ('/estadisticas','/usuarios','/stats'):
            send(cid,private_stats_report(dbc),True)
            return
        if cmd=='/pending':
            with dbc() as c:
                rows=c.execute("""SELECT p.id,p.telegram_id,d.email,d.amount_mxn
                    FROM payments p LEFT JOIN bot_payment_details d ON d.payment_id=p.id
                    WHERE p.status='pending' ORDER BY p.id LIMIT 25""").fetchall()
            report="\n".join("#"+str(r["id"])+" | "+str(r["telegram_id"])+
                             " | "+str(r["email"] or "sin correo")+
                             " | $"+str(r["amount_mxn"] or "?")+" MXN" for r in rows)
            send(cid,"💳 Pagos pendientes:\n"+(report or "Ninguno.")+
                 "\n\n/verpago ID permite ver el comprobante. "
                 "Solo aprueba si confirmaste el depósito en el banco.")
            return
        if cmd in ('/verpago','/asignarcorreo','/approve','/reject'):
            if len(bits)<2 or not bits[1].isdigit():
                send(cid,"Uso: "+cmd+" ID"+(" correo" if cmd=='/asignarcorreo' else ""));return
            payment_id=int(bits[1])
            if cmd=='/verpago':
                payments.view(cid,payment_id)
            elif cmd=='/asignarcorreo':
                if len(bits)<3:
                    send(cid,"Uso: /asignarcorreo ID correo");return
                payments.assign_email(cid,tid,payment_id,bits[2].strip())
            else:
                if cmd=='/approve' and len(bits)>2:
                    send(cid,"La suscripción dura un mes calendario. Usa /approve ID");return
                payments.decide(tid,cid,payment_id,cmd=='/approve')
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
            with dbc() as c:
                replies=c.execute("""SELECT message,created_at FROM support_ticket_replies
                   WHERE ticket_id=? ORDER BY id LIMIT 30""",(int(bits[1]),)).fetchall()
            history='\n'.join('↳ '+str(x['created_at'])+' | '+str(x['message'])[:350]
                             for x in replies)
            send(cid,"🆘 Ticket #"+str(r["id"])+" ("+r["status"]+")\n"+
                 "Usuario: "+str(r["telegram_id"])+"\n"+r["message"]+
                 ("\n\nRespuestas:\n"+history if history else ""))
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
                stamp=iso(now())
                c.execute("UPDATE support_tickets SET updated_at=? WHERE id=?",
                          (stamp,int(bits[1])))
                c.execute("""INSERT INTO support_ticket_replies
                    (ticket_id,operator_id,message,created_at) VALUES(?,?,?,?)""",
                    (int(bits[1]),tid,bits[2][:3000],stamp))
            send(cid,"✅ Respuesta enviada.")
        elif cmd=='/close':
            if len(bits)<2 or not bits[1].isdigit():
                send(cid,"Uso: /close ID");return
            with dbc() as c:
                r=c.execute("SELECT telegram_id FROM support_tickets WHERE id=? AND status='open'",(int(bits[1]),)).fetchone()
                res=c.execute("""UPDATE support_tickets SET status='closed',
                   updated_at=? WHERE id=? AND status='open'""",
                   (iso(now()),int(bits[1])))
            send(cid,"Ticket cerrado." if res.rowcount else "No está abierto.")
            if res.rowcount and r:
                try: send(r['telegram_id'],"✅ Soporte POTV | Ticket #"+bits[1]+" cerrado. Si necesitas más ayuda, abre un nuevo ticket desde 🆘 Soporte.",True)
                except Exception: pass
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

    def handle_callback(callback):
        user=callback.get('from') or {}
        msg=callback.get('message') or {}
        chat=msg.get('chat') or {}
        tid=user.get('id')
        cid=chat.get('id')
        data=callback.get('data') or ''
        try:
            tg('answerCallbackQuery',{'callback_query_id':callback['id']})
        except Exception: pass
        if not tid or chat.get('type')!='private' or int(cid)!=int(tid) or not is_admin(tid):
            return
        bits=data.split(':')
        if len(bits)!=3 or not bits[2].isdigit():
            return
        category,action,number=bits
        item_id=int(number)
        if category=='admin' and action=='stats':
            send(cid,private_stats_report(dbc),True)
            return
        if category=='payment':
            if action=='view':
                payments.view(cid,item_id)
            elif action=='confirm':
                with dbc() as db:
                    p=db.execute("SELECT status FROM payments WHERE id=?",
                                 (item_id,)).fetchone()
                if not p or p['status']!='pending':
                    send(cid,'Ese pago ya no está pendiente.')
                    return
                tg('sendMessage',{'chat_id':cid,
                    'text':'⚠️ Pago #'+str(item_id)+
                    '\nAntes de activar, confirma que el depósito aparece realmente en la cuenta bancaria y coincide en importe, fecha y referencia. ¿Lo verificaste?',
                    'reply_markup':json.dumps({'inline_keyboard':[
                        [{'text':'✅ Sí, confirmé el dinero en el banco',
                          'callback_data':'payment:approve:'+str(item_id)}],
                        [{'text':'Cancelar','callback_data':'payment:cancel:'+str(item_id)}]]},
                        ensure_ascii=False)})
            elif action=='approve':
                payments.decide(tid,cid,item_id,True)
            elif action=='reject':
                payments.decide(tid,cid,item_id,False)
            elif action=='cancel':
                send(cid,'Sin cambios. El comprobante sigue pendiente.')
        elif category=='ticket':
            if action=='reply':
                set_flow(tid,'admin_reply_ticket:'+str(item_id))
                send(cid,'✍️ Escribe tu respuesta para el ticket #'+str(item_id)+
                     '. La mandaré únicamente al cliente. /cancelar para salir.',True)
            elif action=='close':
                admin_command(tid,cid,'/close '+str(item_id))

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
        # Save customer display name for the private operator inbox.
        try:
            g['upsert_user'](user)
        except Exception as exc:
            print('POTV user update failed:',type(exc).__name__,flush=True)
        if cmd=='/id':
            send(cid,"Tu ID de Telegram: "+str(tid));return
        if cmd=='/activaradmin':
            try:
                if not is_group_owner(tid):
                    send(cid,"No pude confirmar que esta cuenta de Telegram "
                         "sea la propietaria del supergrupo oficial POTV. "
                         "Comprueba desde el grupo que eres el propietario "
                         "y vuelve a intentarlo. Nunca compartas códigos.",True)
                    return
                with dbc() as c:
                    c.execute("""INSERT INTO bot_operators VALUES(?,?,?)
                      ON CONFLICT(telegram_id) DO UPDATE SET
                      role=excluded.role""",(tid,'owner',iso(now())))
                send(cid,"✅ Administración POTV activada.\n"
                     "En este chat recibirás comprobantes, tickets y nuevos "
                     "registros de cuentas, todos en privado.\n"
                     "📊 Estadísticas de usuarios: /estadisticas\n"
                     "Pagos: /pending, /verpago ID, /approve ID y /reject ID.\n"
                     "Personalizar imagen OXXO: /configpago.",True)
                tg("sendMessage",{"chat_id":cid,
                    "text":"📊 Panel privado de POTV",
                    "reply_markup":json.dumps({"inline_keyboard":[
                       [{"text":"📊 Consultar estadísticas",
                         "callback_data":"admin:stats:0"}]]},
                         ensure_ascii=False)})
                with dbc() as c:
                    pending=c.execute("SELECT id FROM payments WHERE status='pending' ORDER BY id DESC LIMIT 15").fetchall()
                    tickets=c.execute("""SELECT id,telegram_id,message FROM support_tickets
                       WHERE status='open' ORDER BY id DESC LIMIT 15""").fetchall()
                for entry in pending:
                    inbox.notify_payment(entry['id'])
                for entry in tickets:
                    inbox.notify_ticket(entry['telegram_id'],entry['id'],entry['message'])
            except Exception as exc:
                print("POTV admin claim failed:",
                      type(exc).__name__,flush=True)
                send(cid,"No se pudo verificar la titularidad del grupo. "
                     "Asegúrate de que el bot sea administrador del grupo.")
            return
        if cmd in ('/estadisticas','/usuarios','/stats',
                   '/pending','/verpago','/asignarcorreo','/approve','/reject',
                   '/tickets','/ver','/reply','/close','/anuncio'):
            admin_command(tid,cid,text);return
        if cmd=='/configpago':
            if not is_admin(tid):
                send(cid,'Solo administración puede configurar la imagen.');return
            set_flow(tid,'admin_payment_image')
            send(cid,'📸 Envíame la imagen OXXO en una foto o archivo JPG/PNG. Se mostrará a todos los clientes en medios de pago. /cancelar para salir.',True)
            return
        if cmd=='/cancelar':
            set_flow(tid)
            with dbc() as c:
                c.execute("DELETE FROM bot_payment_drafts WHERE telegram_id=?",(tid,))
            send(cid,"Operación cancelada.",True);return
        if is_admin(tid) and message.get('reply_to_message') and text and not text.startswith('/'):
            original_id=(message.get('reply_to_message') or {}).get('message_id')
            if original_id and inbox.reply_to_message(tid,original_id,text):
                return
        if is_admin(tid) and str(flow(tid) or '').startswith('admin_reply_ticket:') and text and not text.startswith('/'):
            ticket=flow(tid).split(':')[-1]
            set_flow(tid)
            admin_command(tid,cid,'/reply '+ticket+' '+text)
            return
        if cmd in ('/start','/menu') or text=='↩️ Menú principal':
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
        if cmd in ('/descargar','/app') or text=='📥 Descargar aplicación':
            download(cid);return
        if cmd=='/mitickets' or text=='🎫 Mis tickets':
            with dbc() as db:
                rows=db.execute("""SELECT id,status,message FROM support_tickets
                    WHERE telegram_id=? AND message<>'Solicitud de compra POTV'
                    ORDER BY id DESC LIMIT 10""",(tid,)).fetchall()
            body='\n'.join('#'+str(r['id'])+' | '+r['status']+' | '+r['message'][:90]
                           for r in rows) or 'Aún no tienes tickets.'
            send(cid,'🎫 Tus tickets POTV\n'+body+
                 '\n\nPara crear otro, selecciona «🆘 Soporte».',True)
            return
        if cmd=='/soporte' or text=='🆘 Soporte':
            set_flow(tid,'support')
            send(cid,"🆘 Soporte POTV\nCuéntanos qué pasó e incluye el correo con el que registraste POTV, tu dispositivo y la versión de la app.\n"
                 "Se creará un ticket que atenderemos en privado.\n"
                 "No envíes contraseñas ni datos bancarios.\n"
                 "Para cancelar: /cancelar",True)
            return
        if cmd in ('/medios','/formaspago') or text=='💳 Medios de pago' or text.lower() in ('medios de pago','formas de pago','cómo pagar','como pagar'):
            inbox.send_guide(cid)
            send(cid,g['PAYMENT_TEXT']+
                 '\n\nDespués de pagar, pulsa «📤 Enviar comprobante». '
                 'Tu suscripción no se activa hasta que confirmemos el depósito.',True)
            return
        if cmd=='/pago' or text in ('📤 Enviar comprobante','💳 Reportar pago'):
            payments.start(tid,cid)
            return
        if cmd=='/cuenta' or text=='👤 Mi cuenta':
            old(dict(message,text="👤 Mi cuenta"));return
        if cmd=='/vincular' or text=='🔗 Vincular app':
            old(dict(message,text="🔗 Vincular app"));return
        if message.get('photo') or message.get('document'):
            if is_admin(tid) and flow(tid)=='admin_payment_image':
                inbox.configure_guide(tid,message)
                return
            payments.receipt(tid,cid,message)
            return
        if text and flow(tid)=='support':
            add_ticket(tid,cid,text);return
        if text and flow(tid)=='payment_info':
            payments.details(tid,cid,text);return
        if text and flow(tid)=='payment_receipt':
            send(cid,"Falta adjuntar la fotografía, JPG, PNG o PDF del comprobante. "
                 "Puedes cancelar con /cancelar.",True);return
        home(cid)

    commands=[
        {"command":"start","description":"Abrir POTV"},
        {"command":"menu","description":"Menú principal"},
        {"command":"planes","description":"Ver planes"},
        {"command":"comprar","description":"Comprar o renovar"},
        {"command":"cuenta","description":"Estado de suscripción"},
        {"command":"pago","description":"Medios de pago y comprobantes"},
        {"command":"medios","description":"Ver medios de pago"},
        {"command":"descargar","description":"Descargar la última APK de GitHub"},
        {"command":"vincular","description":"Vincular POTV"},
        {"command":"soporte","description":"Solicitar asistencia"},
        {"command":"mitickets","description":"Consultar mis tickets"},
        {"command":"grupo","description":"Comunidad oficial"},
        {"command":"ayuda","description":"Guía de uso"},
        {"command":"id","description":"Mi ID de Telegram"},
        {"command":"activaradmin","description":"Administración (propietario)"},
        {"command":"configpago","description":"Guardar imagen OXXO (admin)"}
    ]
    g['KB']=kb
    g['handle_callback']=handle_callback
    return handle,commands
