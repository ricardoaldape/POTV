# POTV animated branding assets

Place the following original, approved transparent **animated WebP** files in this directory without renaming them:

- `POTV_inicio_animado_transparente.webp` — 960 × 640, 60 frames, 2.5 seconds, loops.
- `POTV_loader_animado_transparente.webp` — 360 × 240, 36 frames, 2 seconds, loops.

Flutter registers `assets/branding/` in `pubspec.yaml`. The startup splash and native/WebView playback loader use these local bundled assets. Do not replace them with still PNG frames or download them at runtime.
