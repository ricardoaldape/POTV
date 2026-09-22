# Changelog

## 0.6.1

- Añade Resolver Packs locales para importar/exportar endpoints POTV y addons compatibles sin recompilar.
- Ajustes muestra rutas de resolución VOD reales con desglose de integradas, build, locales y addons.
- El contador de fuentes locales deja de ser el único indicador del motor de resolución.
- La importación de Resolver Packs deduplica endpoints y manifests equivalentes.

## 0.6.0

- Provider Registry unificado para películas, series y anime.
- Source Aggregator paralelo con aislamiento de errores y timeouts por resolver.
- Arranque rápido: POTV deja de esperar resolvers lentos después de encontrar candidatos reproducibles.
- Caché local de resolución y deduplicación de consultas simultáneas.
- Resolvers preconfigurables por build con `POTV_RESOLVER_ENDPOINTS_JSON`.
- Contrato compatible con respuestas `streams`, `results` y `servidores`.
- Clasificación automática de candidatos directos vs WebView.
- Reproducción VOD restringida a backends dentro de POTV; enlaces externos ya no se abren automáticamente.
- Precarga de resolución desde la pantalla de detalle.
- Eliminado definitivamente el fallback de anime que abría proveedores externos.

## 0.1.0-alpha.2

- Redesigned first-run source setup.
- Series detail now includes season and episode browsing.
- Anime description cleanup and episode browser.
- Local playback history and Continue Watching.
- Expanded genres and category browsing.
- Built-in public Mexico TV and sports source registries.
- Verified starter TV/sports channels for a more reliable first launch.
- Sports Hub fallback channel browser.
- Local Stremio-compatible addon support, including compatible Nuvio remote addons.
- Unified source resolution for POTV sources + installed addons.
- AniList episode mapping into compatible series-addon playback.
- Settings content diagnostics.
- Official POTV Telegram community link.

## 0.1.0-alpha.1

- Initial Android / Android TV private alpha.
- Movies, Series and Anime catalog shells.
- Live TV M3U/XMLTV support.
- Sports Hub foundation.
- Native and isolated WebView playback.
- Local POTV Source Protocol support.
