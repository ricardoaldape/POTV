# Auditoría técnica de APK compartidas — POTV (2026-10-14)

**Alcance:** inventario estático de los archivos aportados por los colaboradores y priorización de integraciones compatibles con POTV. Esta fase **no certifica** que una APK externa provea legalmente retransmisión, que sus enlaces estén disponibles ni que sus reproductores soporten video en el entorno del cliente. No se copian secretos, contraseñas, código propietario ni endpoints con credenciales al repositorio.

Se identificaron **14 archivos APK y 13 binarios distintos**. Las dos copias de **App Eventos v2** tienen el mismo hash. Los nombres y números de versiones proceden del manifiesto Android; las tecnologías se infieren de bibliotecas empaquetadas, por lo que no acreditan una API utilizable.

| APK | Paquete Android | Versión | Tecnologías observadas | Enfoque de interoperabilidad |
|---|---|---|---|---|
| kino.apk | `com.arkiv.player.light` | 0.9.62 | QuickJS, FFmpeg, Chromecast, 3 DEX | Analizar interfaz de complementos y errores del reproductor; posible diseño de adaptadores |
| Astra28S.apk | `rapid.player.astra` | 1.0.28 | 5 DEX, componentes SDK de anuncios | Evaluar contratos de contenido sin incorporar publicidad o rastreadores |
| Ibo Player Pro | `com.flextv.livestore` | 3.8 | FFmpeg, 3 DEX | UX IPTV, listas, pistas de audio, navegación |
| Puerta SporTV | `com.puertasport.tvphone` | 3.9 | FFmpeg | Agenda deportiva, relación evento→señal |
| App Eventos v2 (dos copias idénticas) | `com.deporagenda.ec` | 1.0.0 | FFmpeg, 5 DEX | Identificador de evento y selección de stream |
| TOTAL TV | `prueba.teoricacr` | 1.0.15 | Flutter | Estructura de TV, categorías y navegación |
| Fútbol Libre TV | manifiesto pendiente de normalizar | 2.1 según nombre | Chromecast, 7 DEX | Eventos, categorías deportivas y navegación |
| AirTv | `app.zonahackaplicaciones.grofibertv` | 1.5 | 6 DEX | Inventario de TV y señal de reproducción |
| PlayTV ARG-IPTV | `com.playtv.premium` | 20.1 | 2 DEX | Gestión de listas y preferencias |
| XD Player | `com.xdplayer.ibo` | 4.3 | FFmpeg | Reproductor, formatos, pistas y buffering |
| TiviGlass | `com.tiviglass.iptv` | 2.2.5 | FFmpeg | UX TV/EPG, controles remotos |
| LMHD-VIP | `net.lmhd.even` | 4.2 | 4 DEX | Clasificación de señales y eventos |
| app-release.apk (referencia) | `com.example.lol` | 1.0.0 | Flutter, FFmpeg, mpv | Compatibilidad con player alternativo |

## Hallazgos relevantes para POTV

1. **Punto principal de falla actual:** el gateway premium responde pero el servidor de origen no acepta conexión desde la IP del VPS. El protocolo debe ser integrado mediante cuentas de servicio y permisos destinados a POTV; el cifrado por sí solo no restablece conectividad.
2. **Video vs. audio en TV:** se identificó que Media3 declaraba reproducción iniciada al recibir `isPlaying`, aunque pudiera existir sólo audio. En la rama de rescate se añadió notificación por primer fotograma renderizado y un margen de arranque mayor para HLS en vivo. Falta compilar, probar en Android y medir regresiones.
3. **Fuentes fragmentadas:** POTV necesita un registro extensible de proveedores con salud/timeout/failover, EPG y categorización por país/idioma. Las cuentas de servicio autorizadas deben residir únicamente en el backend cifrado, no en APK/JS público.
4. **Sports Hub:** cada evento debe enlazar sólo sus señales válidas; mostrar canales no relacionados no constituye reproducción del evento.
5. **Publicación OTA:** existe una APK firmada para evaluación de socios bajo `partner-review-20261014`. Este tag queda fuera del patrón reconocido por Update Center y **no representa una OTA comercial**.

## Verificaciones pendientes antes de comercializar

- Probar integración independiente de películas, series y anime: la API de origen premium seguía devolviendo **cero fuentes** tras corregir timeouts.
- Conseguir conectividad funcional y autorizado al proveedor premium desde el VPS; verificar HBO, AXN, Discovery, NatGeo, Disney y deportes que procedan del catálogo contratado.
- Probar ESPN 2 y otros canales durante al menos 10–20 minutos en teléfono/Android TV, verificando imagen **y** audio; medir inicio, congelamientos, errores y cambio de señal.
- Completar descompilación estática de las APK aportadas y documentar formatos/API de interoperabilidad sin replicar claves ni código propietario.
- Crear y ejecutar pruebas de regresión y un flujo OTA completo (firmas, incremento de versionCode, descarga y reinstalación preservando datos).

**Regla de calidad:** inventario de binarios, respuesta HTTP 200 y éxito al compilar son pasos necesarios pero insuficientes para anunciar contenido reproducible.
