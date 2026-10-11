# POTV Update Center — Android / Android TV OTA

**Estado:** Implementado en la rama `feat/potv-update-center`. Sólo se considera una
actualización oficial cuando existe una versión publicada y firmada en
**GitHub Releases**. Los artefactos APK de un PR se producen para QA, no para
actualizar instalaciones de producción.

## Comportamiento de la aplicación

- **Ajustes → POTV Update Center**: muestra versión y Android versionCode actuales;
  permite canal **Estable** (sólo releases finales) y **Beta** (también prereleases).
- **Detección pasiva**: al abrir la aplicación o volver del segundo plano, consulta
  como máximo una vez cada **12 horas** si hay una nueva versión. No bloquea
  contenido, no descarga APK ni interrumpe videos. Si existe una actualización
  muestra una barra discreta que abre Update Center.
- **Descarga manual verificada**: sólo permite APK en el repositorio
  `ricardoaldape/POTV`, mediante GitHub HTTPS y SHA-256 publicado en el asset
  oficial. El tamaño también tiene que coincidir. Los archivos se escriben en
  caché privada, se verifican por streaming y se descartan si están truncados
  o alterados. Si la descarga supera 450 MiB, se cancela.
- **Instalación Android**: mediante FileProvider con acceso sólo al archivo
  verificado, y el instalador del sistema tras autorización del usuario.
  En Android 8+ solicita habilitar la instalación desde POTV cuando sea
  necesario. **Nunca se eluden las comprobaciones de firma de Android.**
- **Datos**: si la firma y el ID del paquete coinciden, Android realiza una
  actualización sobre la instalación actual, conservando favoritos, cuentas
  y playlists existentes.
- **OTA de contenido separado**: las fuentes, servidores y catálogos
  configurados se refrescan desde sus propias API sin instalar otra APK.
  El OTA de la aplicación **no** garantiza que el backend de un socio esté
  operativo ni concede derechos de retransmisión.

## Política de releases / publicación

`.github/workflows/publish-ota-release.yml` se ejecuta sólo cuando se publica
un tag compatible y el commit **ya está en main**:

1. Versionar `pubspec.yaml` con un nombre semántico y **versionCode creciente**:
   `version: 0.8.0+13`, después `0.8.1+14`, etc.
2. Para estable crear el tag `v0.8.0` en el commit de `main`. Para beta
   crear `v0.9.0-beta.1` cuando el pubspec tenga
   `version: 0.9.0-beta.1+15`.
3. El workflow realiza `flutter analyze`, `flutter test`, construye la APK
   **con la clave privada de release** de GitHub Secrets, valida que el
   certificado coincida con el pin de producción, genera el archivo SHA-256
   y publica automáticamente la APK en GitHub Releases.
4. GitHub registra el digest SHA-256 de cada asset. Update Center exige
   ese digest **y** la línea `POTV-Version-Code: N` de la nota de release.
   Esta regla evita mostrar releases viejos sin control de versión como
   `v1`, así como APK sin comprobación de integridad.
5. Los artefactos de CI de un PR son build de pruebas, pueden tener firma
   **debug**, y no se publican como updates oficiales.

**Variables/Secrets a configurar en GitHub (Actions):**

- **Secrets existentes/requeridos**: `KEYSTORE_BASE64` (keystore de producción,
  no debug), `KEYSTORE_PASSWORD`, `KEY_PASSWORD`, `KEY_ALIAS`.
- **Variable obligatoria**: `POTV_RELEASE_CERT_SHA256`. Se obtiene con
  `apksigner verify --print-certs app-release.apk` sobre **una APK original
  firmada con la clave que ya tienen los usuarios**, copiando sólo el digest
  SHA-256 del certificado (64 caracteres, sin dos puntos). El workflow
  **rechaza** la publicación si falta o no coincide.
- **Variables de contenido autorizadas**, cuando existan:
  `POTV_PARTNER_CATALOG_URL`, `POTV_PARTNER_SOURCES_URL`,
  `POTV_PARTNER_API_BASE_URL`. Son URL públicas de acceso al gateway;
  **jamás** pongas credenciales de socios en `--dart-define`.
- `TMDB_API_KEY` permanece en GitHub Secrets; configura acceso cuando corresponda.

La firma de pruebas y la firma de producción pueden ser **distintas**:
si instalaste una APK de GitHub Actions de PR y Android rechaza actualizarla
con una release de producción, exporta primero tu configuración desde Ajustes,
y revisa el certificado instalado. No desinstales sin respaldar información
local que no quieras perder. Una vez instalada la versión estable firmada
correctamente, posteriores releases de la misma clave actualizarán encima.

## Prueba OTA end-to-end

- Instala la **primera versión release firmada** de POTV 0.8.0 (código 13)
  desde su GitHub Release; comprueba versión en Update Center.
- Publica a continuación una release de prueba nueva con versión superior,
  por ejemplo `0.8.1+14`, con su tag `v0.8.1` y la misma keystore.
- Abre Ajustes → POTV Update Center → Buscar actualizaciones:
  debe mostrar la nueva versión y sus notas.
- Descarga; verifica progreso, SHA-256, autorización de instalación y que
  Android permite actualizar sobre la app actual. Reabre POTV y verifica
  versión y datos locales.
- Simula falta de red, APK corrupta y firma distinta: **no deben instalarse**.
- Repite con D-pad en Android TV y el canal Beta; confirma que una prerelease
  no aparece en Estable.
- Verifica que catálogo M3U y servidores actualizan independientemente,
  sin nuevo binario (según las API habilitadas).

**Limitaciones intencionales:** No hay instalación silenciosa ni cambios de
código Flutter en caliente. El sistema requiere confirmación del instalador
Android. Tampoco es un mecanismo de actualización de aplicaciones mediante
Google Play; si se distribuye por Play, deberá usarse su sistema de updates.
