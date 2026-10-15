# POTV — contrato permanente de suscripciones

**Obligatorio para todas las versiones, APK, OTA y ramas de actualización.**

La infraestructura de POTV es la fuente de verdad: ninguna actualización
puede quitar ni modificar estas reglas sin una decisión explícita del propietario.

## Reglas de producto

1. Una prueba gratuita por cuenta/correo, de **cinco días exactos (120 horas)**
   desde la creación de la cuenta. El servidor registra el instante UTC.
2. Al vencer la prueba o la suscripción, se bloquea el acceso a POTV.
   Perfiles, historial y preferencias no se eliminan.
3. Los pagos nunca activan automáticamente el servicio. Una persona autorizada
   comprueba el depósito y ordena la activación manual por correo.
4. La duración pagada es **un mes calendario de fecha a fecha**, manteniendo la
   hora local de Ciudad de México. Si falta el día correspondiente en el mes
   siguiente, se utiliza el último día existente; la renovación conserva el
   día de facturación original para regresar a él cuando sea posible.
5. Una renovación de cuenta activa se agrega al final del periodo actual,
   sin descontar los días restantes. Si ha vencido, inicia al autorizarse.
6. Desde diez días exactos antes de terminar una suscripción *pagada*, el aviso
   aparece encima del contenido de Inicio. No es notificación del sistema.
7. Después de pagar, el usuario puede pulsar «Ya pagué: comprobar activación»
   sin reinstalar APK ni borrar su cuenta.
8. La activación se audita con identidad de quien aprobó y, si existe,
   referencia y fecha del comprobante. No hay endpoint público de activación.
9. El backend valida tiempo de servidor y acceso a contenidos protegidos;
   las fechas locales del celular no deben conceder acceso en el servidor.

## Protección contra regresiones

- `tool/verify_subscription_contract.py` comprueba que se mantengan el bloqueo
  de la app, el banner, los modelos de cuentas, la autorización manual y el
  motor de fechas en el backend.
- `backend/potv-bot/test_subscriptions.py` cubre pruebas, vencimientos,
  renovaciones, mes corto/bisiesto, alertas y duplicidad de recibos.
- `test/subscription_access_test.dart` cubre el bloqueo y el aviso de Flutter.
- Los workflows de CI, construcción APK, pruebas del backend y publicación OTA
  ejecutan el contrato antes de generar o publicar una versión.

## Requisitos antes de distribuir a clientes

- Confirmar entrega de correo / propiedad del email (no solo coincidencia).
- QA Android real: vencimiento, renovación, reinstalación, perfiles y
  reproducción de cada sección (películas, series, anime, TV, deportes).
- Probar que fuentes locales y URL ya resueltas no eludan el vencimiento.
- Comprobar firma/versionCode y sincronización OTA; nunca distribuir APK de
  debug como comercial.

El servidor productivo contiene la configuración y base SQLite privada.
No incorporar credenciales, recibos, tickets ni bases de clientes al repositorio.
