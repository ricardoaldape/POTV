# Sports Hub ES/EN y revisión de fuentes — octubre 2026

## Cambios de producto

- **Sports Hub:** opción de preferencia **Español / English / Todos**, por defecto Español. Se recuerda mediante SharedPreferences.
- **Live TV:** conserva sus categorías, EPG, favoritos y múltiples listas sin alteraciones de interfaz.
- **M3U:** el parser ahora conserva `tvg-language`, `audio-language` o `language` en cada `StreamCandidate`.
- **Selección:** los canales con idioma explícitamente contrario se ocultan al filtrar; los no identificados permanecen visibles. Las señales del idioma elegido aparecen primero; en canales con respaldos se prioriza el stream del idioma solicitado y se conservan las alternativas.
- **Etiquetas:** las tarjetas muestran ES/EN únicamente cuando hay metadata disponible. ES no implica necesariamente doblaje latinoamericano, y los metadatos deben verificarse contra audio real durante QA.

## Inventario LivSports: análisis local sin accesos

Carpeta del usuario analizada localmente, sin instalar APKs ni acceder a servidores privados: **4 APK, 28 TXT** (~104 MB). Los TXT incluyen ~228 mil líneas y 27,613 apariciones de URLs; no contienen líneas `#EXTINF` ni playlists M3U directamente importables. Se detectaron 17,378 huellas de URL únicas y 372 dominios distintos, con numerosas rutas Xtream y parámetros tipo cuenta/contraseña. **No son pruebas de que esas cuentas estén activas ni de disponibilidad de canales concretos**.

Metadatos de APK analizados con Android SDK/ZIP:
- App Eventos v2: WebView/Media3 y componentes de avisos/agenda.
- PlayTV: Media3/HLS/DASH.
- TiviGlass: Media3, marcadores Xtream y reproducción HLS/DASH.
- XD Player: ExoPlayer heredado y marcadores Xtream.

No se copiaron APK, archivos TXT, URLs completas, usuarios ni contraseñas al repositorio. Las funciones se consideran **referencias técnicas**; para integrar código/activos o redistribuir contenido se requiere alcance de licencias y derechos concretos.

## Comprobaciones reales de servicios públicos

Verificados desde la PC HP mediante descargas de manifiestos, sin comprobar descodificación de video:
- IPTV-org MX: 173 entradas anunciadas; sin campo `tvg-language`.
- Dearbulut MX: 172 entradas; 168 `spa`, 4 bilingües `spa;eng`.
- IPTV-org deportes: 460 entradas; sin idioma declarado.
- Dearbulut deportes: 409 entradas; 58 etiquetadas `spa`, 98 `eng`; otras lenguas y datos sin clasificar.
- Los manifiestos HLS de ADN 40, Canal 22, TV 4.3, FIFA+ Hispanic y Red Bull TV ES respondieron; falta prueba física Android.
- Manifest Stremio de Cinehack, Torrentio, PiGamer, NuvioSports, RTVE y FTV respondió HTTP 200, sin verificación de streams VOD.

Las listas públicas se modifican y pueden contener URLs no autorizadas para redistribución. **No añadir contenido de pago o cuentas compartidas como fuente de lanzamiento**. Las variables de catálogo/API autorizado de NOVA/LivSports aún requieren configuración.

## Criterios de incorporación

1. **Listo para interfaz:** metadatos de idioma, taxonomía y orden de preferencia con pruebas automáticas.
2. **Listo para QA:** playlist o API explícitamente autorizada para POTV, IDs de canales, categorías y EPG comprobables.
3. **Listo para exhibir en demo:** imagen y sonido reproducidos en Android, idioma real confirmado, estabilidad, permisos y región de transmisión.
4. **Listo para comercializar:** derechos de explotación/retransmisión correspondientes, vigencia, cuentas de integración propias, firma oficial, pruebas del sistema de cobro y activación.

Este PR **no valida credenciales compartidas**, no altera `main` y no añade una fuente privada nueva por defecto.
