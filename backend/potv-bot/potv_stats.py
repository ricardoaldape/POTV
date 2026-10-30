"""POTV private account notifications and owner-only statistics.

'Active with access' means an unexpired trial or paid account.
'Recently used' means a successful authenticated app request in the last 7 days.
Neither number pretends to measure simultaneous viewers.
"""
from datetime import datetime, timedelta, timezone
from subscription_policy import LOCAL_TZ, subscription_state, aware


def snapshot(dbc, at=None):
    stamp = at or datetime.now(timezone.utc)
    last_week = stamp - timedelta(days=7)
    last_day = stamp - timedelta(days=1)
    result = dict(
        registered=0, new_24h=0, new_7d=0, access_current=0,
        trial_current=0, paid_current=0, without_access=0,
        active_7d=0, linked_telegram=0,
    )
    with dbc() as db:
        accounts = db.execute(
            """SELECT id,created_at,telegram_id,
               subscription_status,subscription_expires_at FROM app_accounts"""
        ).fetchall()
        recently = {
            row["account_id"] for row in db.execute(
                "SELECT account_id FROM app_account_activity WHERE last_seen_at>=?",
                (last_week.isoformat(),)
            )
        }
    for account in accounts:
        result["registered"] += 1
        if account["telegram_id"] is not None:
            result["linked_telegram"] += 1
        created = aware(account["created_at"])
        if created and created >= last_day:
            result["new_24h"] += 1
        if created and created >= last_week:
            result["new_7d"] += 1
        if account["id"] in recently:
            result["active_7d"] += 1
        entitlement = subscription_state(
            account["subscription_status"], account["subscription_expires_at"], stamp
        )
        if entitlement["access_allowed"]:
            result["access_current"] += 1
            if account["subscription_status"] == "trial":
                result["trial_current"] += 1
            else:
                result["paid_current"] += 1
        else:
            result["without_access"] += 1
    return result


def report(dbc):
    m = snapshot(dbc)
    return (
        "📊 POTV | Estadísticas privadas\n\n"
        "👤 Cuentas registradas: " + str(m["registered"]) +
        "\n✅ Con acceso vigente: " + str(m["access_current"]) +
        "\n🎁 En prueba gratuita vigente: " + str(m["trial_current"]) +
        "\n💎 Pagadas/permanentes vigentes: " + str(m["paid_current"]) +
        "\n⏸️ Sin acceso vigente: " + str(m["without_access"]) +
        "\n📲 Con actividad autenticada en 7 días: " + str(m["active_7d"]) +
        "\n🔗 Vinculadas a Telegram: " + str(m["linked_telegram"]) +
        "\n🆕 Nuevas últimas 24 h: " + str(m["new_24h"]) +
        "\n📅 Nuevas últimos 7 días: " + str(m["new_7d"]) +
        "\n\nLa actividad significa iniciar sesión o hacer una solicitud "
        "autenticada a POTV; NO indica cuántos ven contenido simultáneamente."
    )


def deliver(dbc, tg, targets, authorized, log=print):
    """Attempt delivery after committed registrations; never post to a group."""
    recipients = []
    for tid in targets():
        if isinstance(tid, int) and tid > 0 and authorized(tid):
            recipients.append(tid)
    if not recipients:
        return 0
    stamp = datetime.now(timezone.utc)
    with dbc() as db:
        queue = db.execute(
            """SELECT e.account_id,e.created_at,e.attempts,
               a.email,a.username,a.subscription_status
               FROM bot_account_registration_events e
               JOIN app_accounts a ON a.id=e.account_id
               WHERE e.delivered_at IS NULL
               AND (e.next_attempt_at IS NULL OR e.next_attempt_at<=?)
               ORDER BY e.created_at ASC LIMIT 30""",
            (stamp.isoformat(),)
        ).fetchall()
    sent = 0
    for item in queue:
        when = aware(item["created_at"])
        local = when.astimezone(LOCAL_TZ).strftime("%d/%m/%Y %H:%M") if when else "Sin fecha"
        # No passwords, login tokens, full account ID, or private bank details.
        body = (
            "🆕 POTV | Nueva cuenta registrada\n\n"
            "👤 Nombre: " + str(item["username"])[:65] +
            "\n📧 Correo: " + str(item["email"])[:254] +
            "\n🕒 Registro (CDMX): " + local +
            "\n🎁 Prueba de 5 días al registrarse"
            "\n\nUsa /estadisticas para ver el total de usuarios."
        )
        success = True
        for tid in recipients:
            try:
                tg("sendMessage", {"chat_id": tid, "text": body})
            except Exception as exc:
                log("POTV private registration notification error:", type(exc).__name__)
                success = False
        with dbc() as db:
            if success:
                db.execute(
                    """UPDATE bot_account_registration_events
                    SET delivered_at=?,attempts=attempts+1,next_attempt_at=NULL
                    WHERE account_id=? AND delivered_at IS NULL""",
                    (datetime.now(timezone.utc).isoformat(),item["account_id"])
                )
                sent += 1
            else:
                attempts = item["attempts"] + 1
                delay = min(3600, 30 * (2 ** min(7, attempts-1)))
                db.execute(
                    """UPDATE bot_account_registration_events
                    SET attempts=attempts+1,next_attempt_at=?
                    WHERE account_id=? AND delivered_at IS NULL""",
                    ((datetime.now(timezone.utc) + timedelta(seconds=delay)).isoformat(),
                     item["account_id"])
                )
    return sent
