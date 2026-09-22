# POTV Alpha 0.1.0 Alpha 2 Test Checklist

This build is for private functional testing on Android phones and Android TV.

## What changed since Alpha 1

- Series now open their detail page first instead of showing a numeric season/episode dialog.
- Series detail includes real seasons and episode cards when metadata is available.
- Anime descriptions are sanitized so HTML tags such as `<i>` are not shown.
- Anime exposes episode browsing from AniList episode counts.
- Playback progress is saved locally and Home includes **Continuar viendo**.
- More categories were added, together with category browsing / **Ver más**.
- Settings are directly reachable from Home.
- The official POTV Telegram community is linked from Settings.
- Stremio-compatible remote addons can be installed locally; compatible Nuvio remote addons use the same path.
- Movie/series playback now combines POTV HTTP sources and installed compatible addons.
- Anime can map AniList + absolute episode to IMDb/season/episode for compatible series addons when a mapping is available.
- Live TV loads public Mexico channel registries automatically and still accepts the user's own M3U.
- POTV includes a small verified starter set so TV does not depend entirely on a remote playlist being reachable.
- Sports Hub loads public sports channels and can offer available channels when automatic event matching cannot identify one.
- Settings includes content diagnostics for TV, sports, VOD sources and addons.

## What should work without configuration

- Home catalog for Movies and Series through the no-key metadata fallback; TMDB remains optional for this alpha.
- Anime catalog through AniList.
- Movies / Series / Anime selector.
- Expanded category browsing.
- POTV navigation on touch and TV layouts.
- Search for Movies and Series.
- Live TV with built-in public starter channels.
- Sports Hub event discovery and sports-channel browsing.
- Player UI with audio, subtitles, quality and server switching.
- A public playback test under **Settings > Probar reproductor**.

## VOD playback

Movies, series and anime use the unified source resolver.

POTV checks, on device:

1. configured POTV HTTP sources;
2. installed compatible Stremio/Nuvio remote addons;
3. for Anime, AniList episode mapping is attempted before compatible series-addon resolution.

No source endpoint, resolved URL, playback header or viewing history is sent to POTV infrastructure.

### Expected UX

- Movie poster -> resolve -> play.
- Series poster -> detail -> season -> episode -> resolve -> play.
- Anime poster -> detail -> episode -> resolve -> play.
- Returning to Home after playback -> **Continuar viendo** with local progress.

## Live TV

POTV automatically loads public Mexico TV lists and merges them with the user's configuration.

The user can also add:

- an M3U URL; or
- a local M3U/M3U8/TXT file.

XMLTV can be configured separately. If a custom M3U contains an embedded EPG URL, POTV can pick it up locally.

Lists and TV configuration remain on the device.

## Sports Hub

Sports Hub combines:

- public sports event metadata;
- public sports-channel registries;
- local Live TV channels;
- local EPG when configured.

When an event matches a local/available channel, POTV offers **VER**. If automatic matching is inconclusive, **CANALES** opens available sports channels instead of leaving the event as a dead end.

## Sources and addons

Open **Settings > Fuentes y addons**.

### POTV sources

POTV Source Protocol endpoints are called directly by the client device.

See `docs/SOURCE_PROTOCOL.md`.

### Stremio / Nuvio remote addons

Paste an addon URL or `manifest.json`. POTV validates the manifest before storing it locally.

This alpha only consumes direct HTTP/HTTPS playback URLs returned by compatible addons. Torrent-only streams are intentionally ignored by the current player engine.

## Important alpha limits

- Anime provider-specific adapters are still being expanded beyond the generic/local and addon paths.
- Phone-to-TV configuration transfer is manual in this alpha; encrypted LAN pairing remains pending.
- Subscription/paywall and the production updater are intentionally disabled in this private testing build.
- The alpha APK uses temporary test signing; production releases will use the dedicated POTV signing key.
- Alpha 2 already uses the approved POTV pirate-play identity: play triangle with crossed bones, adapted for launcher and Android TV.

## Suggested test order

1. Open POTV and review Movies, Series and Anime.
2. Check categories and **Ver más**.
3. Open a Series and verify season/episode navigation.
4. Open an Anime and verify clean description text and episode buttons.
5. Open **Settings > Probar reproductor**.
6. Pause playback and test Audio, Subtitles, Calidad and Servidores.
7. Open Live TV without adding any list and try the built-in public channels.
8. Open Sports Hub and try both **VER** and **CANALES** where available.
9. Add a compatible remote addon under **Fuentes y addons** and test movie/series resolution.
10. Play partially, return to Home, and verify **Continuar viendo**.
11. On Android TV, verify D-pad focus, poster expansion and navigation.
