# Changelog

## 0.6.3

- Elimina Internet Archive Series del pool automático para impedir falsos positivos de series modernas.
- Endurece la validación de películas de dominio público: título y año deben coincidir también en metadata.
- Distingue explícitamente VOD de contenido en vivo; una duración desconocida ya no muestra “EN VIVO” en películas/series/anime.
- TV y deportes marcan sus sesiones como live de forma explícita.
- El estado de resolución separa rutas externas configuradas de fallbacks integrados.
- Si no existe ninguna fuente VOD externa, Play permite pegar una sola URL, instalarla y reintentar automáticamente sin navegar por menús técnicos.

## 0.6.2

- Añade una entrada única “Agregar fuente” con detección automática de addons compatibles, repositorios Nuvio JS y listas M3U.
- Añade runtime local de plugins Nuvio compatibles: `getStreams(tmdbId, mediaType, season, episode)` se integra al ResolverPool de POTV.
- El runtime usa QuickJS-NG mediante `quickjs_engine` para compatibilidad con builds Android modernos.
- Anime traduce AniList/episodio a TMDB/temporada/episodio antes de consultar plugins compatibles.
- Los plugins instalados se consultan automáticamente al pulsar Play y sus resultados pasan por ranking, probe y failover existentes.
- Las fuentes avanzadas quedan fuera del flujo principal y la pantalla muestra plugins instalados con activación/desactivación.
- POTV reconoce repositorios CloudStream y los identifica de forma explícita; el bridge `.cs3` todavía no forma parte de este build.

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
