# POTV Alpha 0.1 Test Checklist

This build is for private functional testing on Android phones and Android TV.

## What should work without configuration

- Home catalog for Movies and Series through the metadata fallback.
- Anime catalog through AniList.
- POTV navigation on touch and TV layouts.
- Search for Movies and Series.
- Poster click behavior:
  - Movie: immediately resolves local sources and opens playback when a candidate exists.
  - Series: asks season/episode, then resolves and plays.
  - Anime: asks absolute episode, then resolves and plays.
- Player UI with audio, subtitles, quality and server switching.
- A public playback test under Settings > Probar reproductor.

## Live TV

You can add either:

- an M3U URL; or
- a local M3U/M3U8/TXT file.

XMLTV can be configured separately. If an M3U contains an embedded EPG URL, POTV can pick it up locally.

Live TV source configuration remains on the device.

## Sports Hub

Sports metadata is public event metadata. POTV tries to relate an event to channels from your local Live TV + EPG configuration.

If no local channel matches the event, the event remains visible but playback stays disabled.

## Local VOD sources

Settings > Fuentes locales accepts POTV Source Protocol endpoints.

The endpoint is stored locally and called directly from the device. POTV servers do not receive the endpoint, result, stream URL, headers or viewing history.

See `docs/SOURCE_PROTOCOL.md`.

## Important alpha limits

- Built-in movie/series/anime provider adapters are still being expanded.
- Phone-to-TV configuration transfer is manual in this alpha; encrypted LAN pairing is next.
- Subscription/paywall and production updater are intentionally not enabled in this private testing build.
- The alpha APK uses temporary test signing; production releases will use the dedicated POTV signing key.
- The launcher artwork is temporary alpha branding; final artwork will use the supplied POTV brand asset.

## Suggested test order

1. Open POTV and move through Movies, Series and Anime.
2. Focus posters on Android TV and verify card expansion.
3. Open Settings > Probar reproductor.
4. Pause playback and test Audio, Subtitles, Calidad and Servidores.
5. Add a Live TV list if you have one and test channel playback.
6. Add XMLTV if available and verify current-program labels.
7. Open Sports Hub and verify event/channel matching.
8. Configure a POTV HTTP source and test poster -> resolve -> play.
