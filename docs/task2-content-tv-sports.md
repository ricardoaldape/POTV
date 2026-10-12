# POTV Task 2 — contenido, TV y Sports Hub

Esta rama parte de Task 1 y conserva el trabajo previo de TV/Sports/reproductor.

## Producto

- YouTube queda eliminado del producto: rutas, pantallas, cliente, repositorios, tests y dependencia.
- La interfaz comercial ya no muestra configuración M3U/XMLTV ni nombres técnicos de addons/servidores.
- El motor interno conserva soporte M3U y XMLTV/EPG para fuentes administradas.
- El catálogo autorizado acepta aliases normalizados de Xtream entregados por el gateway POTV; las credenciales Xtream no se incorporan en la APK.
- Los canales aceptan transportes HTTPS HLS (.m3u8) y DASH (.mpd), primarios o de respaldo.
- Sports Hub conserva agenda por fecha/deporte, idioma preferido y TV deportiva.
- Un evento sólo se habilita cuando tiene streams explícitamente asociados al evento o una coincidencia EPG verificada; nunca se enlaza a un canal genérico por categoría.
- Reproducción nativa sigue teniendo prioridad sobre WebView. Los embeds quedan como compatibilidad y mantienen el endurecimiento existente.

## Referencias técnicas reutilizadas

La auditoría previa de App Eventos, PlayTV, TiviGlass y XD Player se usa únicamente como referencia de arquitectura: agenda, Media3/ExoPlayer, HLS/DASH y esquemas Xtream. No se copiaron credenciales, endpoints privados ni contenido protegido al repositorio.

## Gate

La rama debe pasar analyze, tests y build APK en GitHub. La reproducción real y las señales autorizadas se prueban después, como pidió el propietario, una vez terminadas las tres tareas en GitHub.
