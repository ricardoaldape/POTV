# POTV OTA — operación segura

POTV separa los APK de QA de las actualizaciones OTA de producción.

## Reglas

- El identificador Android debe permanecer en `com.potv.potv`.
- Toda OTA debe incrementar `versionCode` en `pubspec.yaml`.
- Versiones estables usan `X.Y.Z+CODE`.
- Betas usan `X.Y.Z-beta.N+CODE`.
- El asset oficial debe llamarse exactamente `POTV-vX.Y.Z.apk` o
  `POTV-vX.Y.Z-beta.N.apk`.
- El cuerpo de la GitHub Release incluye `POTV-Version-Code: CODE`.
- Nunca publicar una OTA firmada con Android Debug.

## Publicación

El workflow **POTV OTA release on HP** corre únicamente en el runner HP autorizado.

1. Ejecutarlo con `publish=false`.
2. El runner ejecuta tests, restaura temporalmente la llave de producción,
   compila y verifica paquete/versionCode/certificado.
3. Probar el candidato guardado en `C:\POTV-ReleaseCandidates`.
4. Configurar la variable del repositorio `POTV_RELEASE_CERT_SHA256` con
   el fingerprint SHA-256 del certificado de producción si todavía no existe.
5. Ejecutar de nuevo con `publish=true`.
6. GitHub publica el APK. GitHub expone el SHA-256 del asset en la API y
   Update Center sólo acepta metadata oficial consistente.

Los secretos de firma se eliminan del workspace al terminar.

## Validaciones en el teléfono

Antes de abrir el instalador Android, POTV comprueba:

1. Release oficial del repositorio POTV.
2. Tag y nombre del APK válidos.
3. `versionCode` superior al instalado.
4. Tamaño máximo permitido.
5. SHA-256 exacto después de descargar.
6. Package ID `com.potv.potv`.
7. Certificado Android compatible con la instalación actual.

Una descarga ya verificada se reutiliza al volver a Update Center. Un APK
corrupto se elimina y nunca se entrega al instalador.

## QA

Los workflows ordinarios de CI sólo generan APK **debug/QA**. Esos APK no son
candidatos OTA. La producción sale exclusivamente del workflow firmado del HP.

## Prueba física mínima antes de publicar

- Abrir Update Center y confirmar versión/código instalados.
- Buscar la actualización en Estable o Beta.
- Descargar y verificar SHA-256.
- Confirmar que la prevalidación de paquete/firma/versionCode pasa.
- Instalar y verificar que perfiles, favoritos y configuración permanecen.
- Abrir de nuevo Update Center y confirmar que ya no ofrece la versión instalada.
