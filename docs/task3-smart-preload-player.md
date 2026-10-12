# POTV Task 3 — Smart Preload y reproductor

## Preparación inteligente

- Al abrir el detalle se resuelven fuentes en segundo plano.
- Se ordenan, comprueban y filtran antes de pulsar reproducir.
- El resultado se guarda sólo en memoria por 2 minutos, con máximo 8 entradas.
- Las URLs firmadas no se persisten en almacenamiento.
- En Android, si el mejor stream es nativo y no necesita headers privados, Media3 precarga 3 segundos en memoria.
- El siguiente episodio se prepara después de que el actual ya inició para evitar competir por ancho de banda.
- La cola de autoplay se limita a 20 episodios.

## Reproductor

- Media3/ExoPlayer 1.11.1 para Android con HLS y DASH.
- Google Cast mediante CastPlayer/MediaRouter.
- Reproducción local/remota desde el mismo control de POTV.
- Audio latino primero; después español, con preferencia por perfil.
- Subtítulos españoles preparados antes de reproducir y activados cuando no hay audio español.
- Autoplay del siguiente episodio respeta la preferencia del perfil.
- Failover mantiene la política existente: recuperación de la misma señal y después cambio automático.
- El botón Atrás conserva una salida determinista al contenido anterior.
- WebView queda como respaldo endurecido; navegación fuera de hosts autorizados y popups siguen bloqueados.

## Consumo y observabilidad

- La precarga se limita a 3 s y sólo a una fuente nativa apta.
- Caché de preparación corta y acotada para limitar RAM.
- No hay sondeo de fuentes en background permanente.
- Se registran localmente por perfil: tiempo de arranque, fallos y tiempo reproducido.
- No se guardan URLs de streams en las métricas.

## Gate GitHub

El cierre se valida con analyze, tests y build APK en GitHub. La prueba física Android se realiza después de terminar las tres tareas en GitHub, según la instrucción del propietario.
