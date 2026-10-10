# POTV — partner content integration (NOVA or another authorized provider)

This is the **client-side contract**, not a claim that NOVA's private API has been connected.
The release APK does not publish a supported API specification. Do not copy embedded
private tokens, impersonate NOVA users, or bypass subscription/device enforcement.

## Content ownership and account boundaries

- POTV accounts, subscriptions, profile data and playback history stay in POTV.
- The partner must **explicitly authorize API access and applicable content rights**.
  Permission to inspect/change an APK does not grant rights to redistribute
  third-party movies, live TV or sport broadcasts.
- POTV should call a POTV-operated HTTPS gateway with a signed, **user-scoped**
  session. That gateway should validate the user's subscription and request
  partner access using server-held credentials and documented API endpoints.
- The gateway must never hand out permanently reusable partner API secrets or
  embed credentials in APK resources, Dart defines, or Git history.
- If partner access is unavailable, the existing locally configured providers
  and user-added M3U/addons must continue functioning.

## Existing integration point

`ConfiguredResolverProvider` already accepts endpoints from
`POTV_RESOLVER_ENDPOINTS_JSON`. A partner gateway can normalize its
authorized source resolution API to the **POTV public contract**:

```json
[
  {
    "id": "authorized_partner",
    "name": "Partner",
    "endpoint": "https://YOUR-POTV-GATEWAY.example/resolve",
    "media_types": ["movie", "tv", "anime"],
    "priority": 5
  }
]
```

**Request:** `GET /resolve?type=movie&tmdb_id=123` or
`GET /resolve?type=tv&tmdb_id=123&season=1&episode=2`.
For anime, `anilist_id` is sent instead of `tmdb_id`.
`external_id`, `title`, and `year` are provided when available.

**Response (normalized by the partner gateway):**

```json
{
  "data": {
    "sources": [
      {
        "name": "Authorized CDN",
        "streamUrl": "https://media.example/opaque-signed-path",
        "content_type": "video/mp4",
        "language": "es-MX",
        "quality": "1080p",
        "headers": {}
      }
    ]
  }
}
```

Also supported: root `streams`, `sources`, `results`, or `servidores`.
`backend` may explicitly be `native` or `webview`. When the backend is not
declared and a URL has no file extension, POTV now recognizes a declared
media MIME type and can inspect the URL using an HTTP HEAD request before
treating it as an embedded web player.

**Important:** the configuration in the example above has no authorization
header mechanism. For production paid access, use a user-scoped authenticated
gateway and extend the provider to send the appropriate POTV session
credential securely. Do not expose unprotected paid-media resolution endpoints.

## Validation required before announcing partner content works

1. Confirm the actual partner API schema, auth scheme, rate limits and renewal
   flow with NOVA. Document license/usage restrictions.
2. Verify authorized movie, series episode, anime episode, live TV and sports
   sources with test accounts on real Android and Android TV devices.
3. Confirm source validity (200/206, correct MIME and manifest) and check audio
   track language and subtitles. Do not mistake metadata search results for
   playable video sources.
4. Test expired tokens, revoked entitlement, offline partner gateway, stream
   stalls, switching servers, user sign-out and device/session limits.
5. Load-test gateway policies; redact signed URLs and credentials from logs.
6. Ensure OTA configuration changes do not silently change the executable APK;
   require normal signed releases for native/app code updates.

This branch improves **local playback/source plumbing**, but is not a live
NOVA catalog connection. Production access must follow their documented terms.

## Live content mirror: the actual collaboration proof

POTV's Home, Live TV and Sports Hub now read a common `PartnerContentSnapshot`.
This is deliberately **vendor-neutral** and does **not** introduce partner branding,
account creation, checkout screens, payment providers or device-based subscription
limits.

The partner gateway serves **fresh snapshots** from HTTPS. POTV checks for updates
every 2 minutes while the relevant screen is in the foreground, refreshes again
when the app resumes, and retains its last-known snapshot temporarily if the
gateway becomes unreachable. HTTP ETags avoid downloading unchanged payloads.
This is content/configuration refresh, **not executable app hot swapping**.

Set the non-secret GitHub Actions repository variable
`POTV_PARTNER_CATALOG_URL` to the **POTV-authorized content gateway HTTPS URL**.
The value is passed as a Flutter `--dart-define` to Android builds. For example:

```
POTV_PARTNER_CATALOG_URL=https://YOUR-POTV-GATEWAY.example/content/catalog
```

The partner catalog schema is normalized by **our gateway**:

```json
{
  "data": {
    "revision": "catalog-2026-10-20-01",
    "movies": [
      {"tmdb_id": 550, "title": "A Film", "poster": "https://images.example/550.jpg"}
    ],
    "series": [
      {"tmdb_id": 1399, "title": "A Series"}
    ],
    "anime": [
      {"anilist_id": 21, "title": "An Anime"}
    ],
    "channels": [
      {"id": "tv-7", "name": "Channel 7", "group": "News", "stream_url": "https://cdn.example/watch/7"}
    ],
    "sports_channels": [
      {"id": "sport-8", "name": "Sports 8", "stream_url": "https://cdn.example/watch/8"}
    ],
    "sports_events": [
      {"id": "match-1", "sport": "Soccer", "competition": "League", "home": "Home", "away": "Away",
       "starts_at": "2026-10-20T20:00:00Z", "is_live": false}
    ]
  }
}
```

- `tmdb_id` is mandatory for films/series; `anilist_id` for anime, since those
  are the ID spaces POTV's playback coordinator understands today.
- Catalog metadata is **not proof of playback**: movies and episodes still need
  a working resolver endpoint (configured via `POTV_RESOLVER_ENDPOINTS_JSON`)
  and valid user entitlements on the gateway. Movie/channel rights must permit
  the integration.
- `channels` / `sports_channels` are playable URLs with their correct,
  short-lived session authorization. The gateway must not return an unprotected
  public list of paid streams.
- Any newly delivered app-only functionality still requires an explicit
  POTV code change, integration tests and release signing.

**Automated demo:** `test/partner_content_repository_test.dart` changes a
mock gateway from `rev-1` (one movie, one TV channel) to `rev-2`
(two movies, two channels) and checks the new items are reflected **without
changing client code or rebuilding an APK**. It also tests anime, sports,
invalid IDs, invalid stream URLs and offline fallback.

**Real partner acceptance test:** after our gateway is configured with authorized
access, the partner publishes a specific new title, channel, stream or match;
POTV fetches the next catalog revision; confirm the item and play it on Android
and Android TV. No claim of real partner connectivity is made until that passes.

## Upstream app-release watcher

Set GitHub Actions variable `POTV_PARTNER_RELEASE_REPO` to the allowed upstream
GitHub `owner/repo`. Workflow `.github/workflows/partner-release-watch.yml`
checks the latest published release every six hours **after the workflow is
merged to the default branch**, records its tag and asset digest, and creates
a POTV review issue for any new release not already recorded. This is a
version-change alert, **not** blind APK re-signing, private credential reuse
or an automatic app-code merge. Nothing vendor-specific or payment-related is
rendered in the POTV application.
