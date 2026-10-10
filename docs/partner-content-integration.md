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
