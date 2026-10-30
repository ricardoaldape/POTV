# POTV — activación segura de verificación por correo

## Estado y rollout

- **No activar** `POTV_EMAIL_VERIFICATION_ENABLED` hasta distribuir a nuevos usuarios una APK que muestre el código de 6 dígitos y configurar el SMTP propio de POTV.
- El backend añade una tabla de registros pendientes; no cambia ni migra suscripciones existentes.
- El periodo gratuito comienza al verificar el código recibido; un registro pendiente no crea cuenta activa.
- Los códigos expiran a los 15 minutos, admiten 5 intentos y requieren 60 segundos entre envíos.
- Los códigos y las contraseñas se guardan solamente como hashes; la verificación consume el código.
- Sin SMTP o ante fallo de entrega se **rechaza** el registro, nunca se omite la verificación.
- Para activar, guardar credenciales en `/opt/potv-bot/.env` con acceso restringido, nunca en GitHub:
  `POTV_SMTP_HOST`, `POTV_SMTP_PORT=587` (STARTTLS) o `465` (TLS),
  `POTV_SMTP_USER`, `POTV_SMTP_PASSWORD`, `POTV_SMTP_FROM`,
  `POTV_EMAIL_VERIFICATION_ENABLED=true`.
- Después de verificar SMTP y APK, reiniciar solamente `potv-bot`; comprobar `/health`,
  una alta real de prueba con correo controlado, respuesta `202`, código `200`, sesión,
  expiración 120 horas, reenvío, error y sesión previa de un usuario actual.

## CI

Ejecutar `python3 backend/potv-bot/test_email_verification.py` desde el directorio del backend
y las suites de cuentas, pagos, bot y contrato. Reconciliar siempre archivos de producción
con los presentes en GitHub antes de despliegues; no hacer `git pull` indiscriminado
sobre `/opt/potv-bot`, que no es un checkout.
