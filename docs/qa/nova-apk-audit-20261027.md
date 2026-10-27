# POTV — NOVA 1.2.9 and partner APK review (27 October 2026)

## Files and evidence

Inspected NOVA.apk, package com.nova.streaming, version 1.2.9 (build 21),
in C:\Users\familia\Downloads\POTV\compartido. Verified APK signature,
application metadata and decompiled Retrofit interface declarations.

The directory had 17 APK filenames representing 16 SHA-256-distinct binaries
when scanned. Local audit artifacts on the user's PC:

- C:\Users\familia\Downloads\POTV\share-audit\apk_inventory_20261026.json
- C:\Users\familia\Downloads\POTV\share-audit\APK-CONTENT-ENDPOINT-INVENTORY-20261027.json
- C:\Users\familia\Downloads\POTV\share-audit\NOVA-1.2.9-TECHNICAL-AUDIT.json

Do not commit APK binary, reverse-engineered proprietary code, tokens or
unapproved provider session material to the POTV source repository.

## Verified NOVA Retrofit contract

- Movies: movies/, movies/trending, movies/{id},
  vod/sources/movie/{tmdbId}, sources/movie/{tmdbId}.
- Series: series/, series/{id},
  vod/sources/tv/{tmdbId}/{season}/{episode},
  sources/tv/{tmdbId}/{season}/{episode}.
- Anime: anime/, anime/trending, anime/search,
  sources/anime/{tmdbId}/{season}/{episode}.
- TV: channels/all_lite, channels/, channels/stream/{id},
  channels/{id}/schedule, live/resolve/{channelKey},
  channels/guide/now-next.
- Version: app/version.

These are interface paths, NOT confirmed playable media URLs. Probes to
hostnames found in the APK did not return authenticated catalog JSON. The
exact API base URL and a dedicated provider-issued POTV service account are
still required.

## Implementation, QA and unfinished gates

nova_partner.py is a new opt-in **server-side** service client recognizing
these catalog and playback routes, HTTPS stream backups, and version checking.
nova_partner_test.py verifies the contract offline; nova_partner_smoke.py
requires a private service configuration before it can query real upstreams.

No NOVA credentials are embedded in the POTV client, and no live customer
catalog routes have been enabled by this branch. Before exposing premium
sources, verify POTV customer entitlements and the provider account scope.
A public list of signed premium proxy URLs is not an acceptable substitute.

Still required:
- Connect working licensed NOVA API credentials and approved provider URL.
- Verify real movie, series, anime and TV sources; resolve NFL Network and
  sports events to exact signals, not similar-name channels.
- Normalize catalog updates behind POTV's authenticated gateway with caching.
- Monitor upstream API/release changes; copying updated APK bytecode is not an
  automatic or reliable way to track provider content updates.
- Verify audio/video on a connected Android device, production signing,
  OTA versionCode, signed GitHub Release, and installation.

Other APKs were inventoried; finding an HLS/DASH/Xtream playback engine
does not establish a licensed content feed or prove streams work.

Status: inspected and connector implemented; upstream access and OTA pending.

## Supplement: live production upstream verification

Subsequent read-only checks identified NOVA's two API hosts through its
Retrofit base URL provider and verified their current catalog JSON responses.
This public provider feed advertises 11,000+ live channel entries, including
two NFL Network entries. One NFL Network upstream returned MPEG-TS (188-byte
sync packets) with H.264 video and AC-3-family audio (stream type 0x87).
A second NFL entry delivered a valid HLS manifest. This does not replace
long-duration device playback QA and does not prove other premium channels.

The upstream's marked premium-only channels have withheld stream URLs; a
sample returned HTTP 402 when its stream route was read unauthenticated.
POTV does NOT bypass those entitlements. The owner may need to have the
provider attach their paid entitlement to a distinct POTV service credential
to receive those remaining channels.

Paid POTV accounts receive a first-party, signed-proxy channel view generated
from a periodically refreshed protected snapshot. The public endpoint never
publishes this enrichment without verifying an active POTV account session.
Movie/series/anime resolutions use their actual TMDB/episode identifiers;
embedded-source VOD remains identified as WebView, not misrepresented as
direct playable video.
