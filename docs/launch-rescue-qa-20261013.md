# POTV launch rescue — 2026-10-13 (Mexico City)

## Objective and release gate
Restore playback and navigation without regressing existing anime, movies, series,
TV and sports. Ship only after physical Android acceptance, a consistent production
certificate, and provider entitlement/rights confirmation. No stream URL, credential,
or partner secret belongs in Git.

## Android baseline
- Observed installed app: com.potv.potv v0.8.0 (versionCode 13).
- Android release candidate must be signed with the same permanent production
  certificate as subsequent updates. The phone's installed version is debug-signed
  and cannot be upgraded by an independently signed production APK.
- Debug QA builds now use com.potv.potv.qa so tests cannot replace consumer data.

## Provider outage blocking commercial launch
- POTV gateway published 330 TV entries and 25 sports entries at the time of testing.
- First-byte checks of 355 gateway playback endpoints: 8 delivered MPEG-TS data,
  284 returned HTTP 502, 63 timed out. This is **not** end-to-end decoding.
- VPS connection to configured Xtream host port 8880 times out. The HP can establish
  TCP connectivity to the same host/port. Have the provider investigate allowlists,
  routing and official HTTPS access. Do not embed provider credentials in APKs.
- The gateway catalog's 200 response is not proof that any premium signal works.
- User-scoped entitlement and partner redistribution rights must be verified before
  selling access.

## Authorized-source playlist audit
- Five Mexico/partner-oriented M3U documents: 3,297 raw entries, 3,012 unique.
- Of these, 122 initial HLS and 3 MP4 responses were recognizable. Most other
  entries were HTTP-only, offline, forbidden, or malformed. Short read does not
  prove stable video/audio or rights.
- HTTP-only links must not be made publicly available by disabling transport
  safety checks. Partner should supply valid HTTPS HLS/DASH or secured gateway.

## Client rescue patches
- Mexico source documents load concurrently and have shorter timeouts, preventing
  a failed provider from doubling initial load delay.
- Partner catalog provider honors short cache TTL to avoid downloading on every
  screen invalidation; signed URLs are revalidated as needed.
- Partner gateway streams open in Media3 directly instead of waiting on inconclusive
  HEAD probes. Playback failure is still surfaced by the player.
- Alternative-source menu remains available on error and selecting current source
  retries playback.
- External provider URLs no longer automatically launch another app. Users must
  intentionally open an external source, or prefer an internal web fallback.
- TMDB networking bounded and Cinemeta fallback on API failures.
- Separate QA application package ID for Android builds.

## Checks required before calling version 1 ready
1. Flutter analyzer: no compile/type errors. Ordinary lint notices tracked separately.
2. Flutter tests: catalog, M3U, playback selector, profiles, updates.
3. Build APK from proposed GitHub revision; inspect package ID/certificate/version.
4. On physical Android: grid render, at least one stable channel per section, sound,
   return/back control, select alternate signal, episode playback and 3–5 minute soak.
5. Signed OTA: release newer version and install on production-signed build without
   deleting profiles, favorites or preferences. First production migration from
   differently signed QA APK requires planned data backup/reinstall.
6. Premium release blocker: provider supplies reachable stable source and
   documented commercial distribution rights/entitlement policy.
