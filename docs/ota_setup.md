# Configuración OTA de POTV

## Arquitectura

La app consulta `https://potv.fxqubit.com/version`. Nginx debe publicar esa ruta hacia el endpoint interno del bot:

`GET /api/v1/version/latest`

El endpoint debe leer `/opt/potv-bot/version.json` en cada petición (o recargarlo de forma segura), sin hardcodear la versión en Python.

## version.json

Ejemplo:

```json
{
  "version": "0.8.0",
  "versionCode": 14,
  "apk_url": "https://github.com/ricardoaldape/POTV/releases/download/v0.8.0/app-release.apk",
  "changelog": "- Anime completo\n- OTA\n- Fix de reproducción",
  "mandatory": false,
  "released_at": "2026-09-25T12:00:00Z"
}
```

`versionCode` debe aumentar en cada APK publicada. El cliente compara este valor contra `PackageInfo.buildNumber`.

## Dependencias Flutter

`dio` y `path_provider` ya existen en el pubspec actual.

Añadir manualmente:

```yaml
package_info_plus: ^8.0.0
open_filex: ^4.0.0
```

Usa versiones compatibles con la versión actual de Flutter/Dart del proyecto.

## Integración en main.dart

No se modifica `lib/main.dart` en este PR.

TODO recomendado después de construir el primer frame:

```dart
final update = await UpdateService().checkForUpdate();
if (update != null && context.mounted) {
  await UpdateDialog.show(context, update);
}
```

Conviene envolver la comprobación en `try/catch`: un fallo de red nunca debe impedir iniciar POTV.

## Backend Python

En `/opt/potv-bot/app.py`, el servidor HTTP debe exponer:

```python
@app.get("/api/v1/version/latest")
def latest_version():
    with open("/opt/potv-bot/version.json", "r", encoding="utf-8") as fh:
        return json.load(fh)
```

Adapta el decorador al framework que ya use el bot (Flask/FastAPI/etc.); no levantes un segundo framework HTTP si el proceso actual ya dispone de uno.

## Nginx

Dentro del bloque HTTPS de `potv.fxqubit.com`, publica una ruta pública simple:

```nginx
location = /version {
    proxy_pass http://127.0.0.1:PUERTO_DEL_BOT/api/v1/version/latest;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
```

Sustituye `PUERTO_DEL_BOT` por el puerto real del proceso existente. Antes de recargar Nginx ejecuta `nginx -t`.

## Android

Android debe permitir instalación desde fuentes externas para la aplicación que abre el APK. La primera actualización puede pedir al usuario habilitar "Instalar apps desconocidas".

El APK OTA debe estar firmado con la misma clave que la versión ya instalada; Android rechazará una actualización firmada con otra clave.

## Publicación

1. Generar APK release firmado.
2. Crear release/tag de GitHub.
3. Subir `app-release.apk`.
4. Incrementar `versionCode`.
5. Actualizar `version.json` en el servidor.
6. Verificar `https://potv.fxqubit.com/version`.
7. Probar desde una instalación anterior de POTV.
