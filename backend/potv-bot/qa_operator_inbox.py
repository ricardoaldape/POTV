"""Offline operator-inbox E2E smoke tests; all Telegram activity is simulated."""
import json,os,sqlite3,tempfile
from datetime import datetime,timedelta,timezone
import os
os.environ['POTV_GROUP_CHAT_ID'] = '-1000000007777'
os.environ['POTV_GROUP_INVITE_URL'] = 'https://t.me/example'
from potv_ops import install

def run():
    with tempfile.TemporaryDirectory() as directory:
        dbfile=os.path.join(directory,'inbox.sqlite3')
        calls=[]
        approvals=[]
        def dbc():
            db=sqlite3.connect(dbfile)
            db.row_factory=sqlite3.Row
            return db
        with dbc() as db:
            db.executescript("""
            CREATE TABLE users(telegram_id INTEGER PRIMARY KEY,first_name TEXT,username TEXT);
            CREATE TABLE app_accounts(telegram_id INTEGER,email TEXT);
            CREATE TABLE payments(id INTEGER PRIMARY KEY AUTOINCREMENT,
                telegram_id INTEGER NOT NULL,reference TEXT UNIQUE NOT NULL,
                photo_file_id TEXT,status TEXT NOT NULL DEFAULT 'pending',
                created_at TEXT NOT NULL,reviewed_at TEXT);
            CREATE TABLE subscriptions(telegram_id INTEGER PRIMARY KEY,
                status TEXT,starts_at TEXT,expires_at TEXT,updated_at TEXT);
            """)
            db.execute("INSERT INTO app_accounts VALUES(123,'maria@example.com')")
        def tg(method,payload):
            calls.append((method,payload))
            if method=='getChatAdministrators':
                assert str(payload['chat_id'])=='-1000000007777'
                return {'result':[{'status':'creator','user':{'id':777}}]}
            if method=='getChatMember':
                return {'result':{'status':'member'}}
            return {'ok':True,'result':{'message_id':len(calls)}}
        def record_user(user):
            with dbc() as db:
                db.execute('INSERT OR REPLACE INTO users VALUES(?,?,?)',
                           (user['id'],user.get('first_name'),user.get('username')))
        class Accounts:
            def account_by_email(self,email):
                if email=='maria@example.com':
                    return {'email':email,'telegram_chat_id':'123'}
            def activate_manual(self,email,**data):
                approvals.append((email,data))
                assert data['approved_by']=='telegram:777'
                return {'subscription_expires_at':
                        (datetime.now(timezone.utc)+timedelta(days=31)).isoformat()}
        deps=dict(tg=tg,dbc=dbc,upsert_user=record_user,
                  handle_message=lambda m:None,
                  now=lambda:datetime.now(timezone.utc),
                  iso=lambda d:d.isoformat(),
                  ADMIN='',BOT_USER='potvoficialbot',BOT_ID='8938958703',
                  PLAN_TEXT='200 MXN mes',PAYMENT_TEXT='Depósito OXXO',
                  ACCOUNT_STORE=Accounts())
        handle,commands=install(deps)
        def incoming(uid,text='',**kwargs):
            message={'from':{'id':uid,'first_name':'María' if uid==123 else 'Propietario',
                             'username':'maria' if uid==123 else 'propietario'},
                     'chat':{'id':uid,'type':'private'},'text':text}
            message.update(kwargs)
            handle(message)
        def callback(uid,data):
            deps['handle_callback']({'id':'callback-'+str(len(calls)),
                     'from':{'id':uid},'message':{'chat':{'id':uid,'type':'private'}},'data':data})
        incoming(123,'/activaradmin')
        with dbc() as db:
            assert db.execute("SELECT COUNT(*) FROM bot_operators").fetchone()[0]==0, "non-owner must not become admin"
        incoming(777,'/activaradmin')
        with dbc() as db:
            assert db.execute("SELECT COUNT(*) FROM bot_operators WHERE telegram_id=777 AND role='owner'").fetchone()[0]==1
        incoming(777,'/configpago')
        incoming(777,photo=[{'file_id':'official-oxxo-image','file_size':555}])
        with dbc() as db:
            assert db.execute("SELECT file_id FROM bot_media_settings").fetchone()[0]=='official-oxxo-image'
        incoming(123,'/start')
        menu=[payload for method,payload in calls if method=='sendMessage' and payload['chat_id']==123][-1]
        assert json.loads(menu['reply_markup'])['is_persistent']
        incoming(123,'/medios')
        assert any(method=='sendPhoto' and p.get('chat_id')==123 and
                   p.get('photo')=='official-oxxo-image' for method,p in calls)
        incoming(123,'/pago')
        payment_intro=[p['text'] for method,p in calls if method=='sendMessage' and p.get('chat_id')==123][-1]
        assert 'CORREO' in payment_intro
        assert 'separados por |' not in payment_intro and 'importe MXN' not in payment_intro
        incoming(123,'maria@example.com')
        incoming(123,photo=[{'file_id':'maria-receipt','file_unique_id':'unique-maria-1'}])
        with dbc() as db:
            payment_id=db.execute("SELECT id FROM payments ORDER BY id DESC").fetchone()[0]
            assert db.execute("SELECT status FROM payments").fetchone()[0]=='pending'
            details=db.execute("SELECT email,amount_mxn,paid_at,bank_reference FROM bot_payment_details WHERE payment_id=?",(payment_id,)).fetchone()
            assert details["email"]=="maria@example.com"
            assert all(not details[key] for key in ("amount_mxn","paid_at","bank_reference"))
        proofs=[p for method,p in calls if method=='sendPhoto'
                and p.get('chat_id')==777 and p.get('photo')=='maria-receipt']
        assert len(proofs)==1 and 'maria@example.com' in proofs[0]['caption']
        assert 'María' in proofs[0]['caption']
        assert len(approvals)==0
        callback(123,'payment:approve:'+str(payment_id))
        assert len(approvals)==0
        callback(777,'payment:confirm:'+str(payment_id))
        assert len(approvals)==0
        assert any('confirmaste' in p.get('text','').lower() or 'verificaste' in p.get('text','').lower()
                   for method,p in calls if method=='sendMessage' and p.get('chat_id')==777)
        callback(777,'payment:approve:'+str(payment_id))
        assert len(approvals)==1
        with dbc() as db:
            assert db.execute("SELECT status FROM payments").fetchone()[0]=='approved'
        incoming(123,'/soporte')
        incoming(123,'Correo maria@example.com. La app muestra pantalla negra.')
        with dbc() as db:
            ticket=db.execute("SELECT id,status,message FROM support_tickets").fetchone()
            assert ticket['status']=='open'
            tid=ticket['id']
        ticket_messages=[(index+1,p) for index,(method,p) in enumerate(calls)
                         if method=='sendMessage' and p.get('chat_id')==777 and
                         'NUEVO TICKET' in p.get('text','')]
        assert len(ticket_messages)==1
        message_id,ticket_notice=ticket_messages[0]
        assert 'María' in ticket_notice['text'] and 'maria@example.com' in ticket_notice['text']
        incoming(777,'Hola María, estamos revisando el problema.',
                 reply_to_message={'message_id':message_id})
        assert any('Hola María' in p.get('text','') and p.get('chat_id')==123
                   for method,p in calls if method=='sendMessage')
        callback(777,'ticket:close:'+str(tid))
        with dbc() as db:
            assert db.execute("SELECT status FROM support_tickets WHERE id=?",(tid,)).fetchone()[0]=='closed'
        assert any(c['command']=='configpago' for c in commands)
        print('PASS inbox: OXXO guide, persistent keyboard, private receipt DM, human callback approval, support DM, reply routing and close')

if __name__=='__main__':
    run()
