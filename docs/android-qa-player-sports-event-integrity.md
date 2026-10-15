# POTV — correcciones tras QA real Android (11 oct 2026)

## Hallazgos de la prueba en Redmi Android 16

- Cuevana e In the Grey: algunos reproductores incorporados muestran interfaces y publicidad propias, y hay enlaces sin señal. POTV debe preferir `PlaybackBackend.native`; una página WebView ajena **no garantiza** reproducción sin anuncios ni control total del video.
- Embed69 (Ted Lasso): hay sobreimpresos publicitarios de terceros en la página incrustada. No se pueden eliminar de forma fiable dentro de un iframe de otro origen mediante el reproductor de Flutter; no prometer adblock universal.
- Sports Hub: la agenda TheSportsDB se confundía con canales que sólo comparten categoría. Se ofrecía TV general para un juego de NFL sin coincidencia de programación.
- Reproductor: el botón de retroceso no salía de forma fiable; se mostraban nombres de proveedores, enlaces internos y textos técnicos.
- Anime: reproducción reportada por usuario como funcional; preservar esta ruta.

## Cambios

1. **Integridad evento → video:** la tarjeta de un encuentro sólo habilita **VER EVENTO** si existe una señal del evento explícitamente entregada por el partner o una coincidencia EPG con ambos equipos y ventana temporal. Sin confirmación, **SIN SEÑAL**; no se muestran canales deportivos genéricos como supuestos enlaces del partido.
2. **Contrato de evento:** `sports_events[].streams`, de un catálogo HTTPS autorizado, une un `id` de evento con candidatos nativos o WebView y `language` / `quality` opcionales. URLs sin HTTPS o credenciales embebidas se rechazan. Las claves de proveedor permanecen en el gateway, no en POTV.
3. **Reproductor UX:** botón regresar con cierre explícito y fallback a inicio, además de Escape/GoBack para mando; nombres de fuentes invisibles en vistas de error, selección y carga. Los registros de depuración mantienen los identificadores necesarios con datos sensibles redactados.
4. **Preferencia nativa:** el historial no adelanta automáticamente un reproductor web ajeno a un stream nativo disponible sólo porque el embed funcionó antes. Fallos repetidos en el nativo siguen habilitando alternativas.

## Catálogo normalizado autorizado (ejemplo de estructura, no emisiones reales)

```json
{
  "data": {
    "revision": "sports-fixtures-demo",
    "sports_events": [
      {
        "id": "demo-event-001",
        "sport": "American Football",
        "competition": "Liga de prueba",
        "home": "Equipo A",
        "away": "Equipo B",
        "starts_at": "2026-10-11T23:00:00Z",
        "is_live": true,
        "streams": [
          {
            "url": "https://media.example.test/authorized-event.m3u8",
            "language": "es-MX",
            "quality": "1080p"
          }
        ]
      }
    ]
  }
}
```

Este JSON es sólo una **fixture**. Los enlaces demo no son transmisiones reales. La API de LivSports debe entregar datos por evento con permiso de uso y reproducción verificable. Un calendario público por sí solo no implica licencia de retransmisión. No integrar TXT masivos de cuentas o credenciales, ni copiar APKs ajenas a la app.

## QA necesaria antes de marcar listo

- Verificar con Redmi: flecha arriba izquierda vuelve al detalle, pestaña o sección previa; sistema Android sigue funcionando.
- Verificar que un partido de NFL no abra Red Bull TV por semejanza de categorías.
- Verificar que un evento de prueba con `streams` explícitos navega a su propia señal.
- Verificar que usuario no ve nombre de addon/proveedor dentro del player; registros técnicos accesibles en modo debug.
- VOD: comprobar si una fuente entrega URL HLS/MP4/DASH reproducible directamente; si sólo entrega un embed con publicidad, documentarlo y preferir fuente nativa con permiso del proveedor.
- No marcar televisión/partido como disponible sólo porque existe un evento en el calendario.
