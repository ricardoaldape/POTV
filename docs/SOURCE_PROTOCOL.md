# POTV Source Protocol v1

POTV sources are configured and stored on the user's device. POTV infrastructure does not maintain a registry of installed source URLs and does not proxy source traffic.

## Request

A source endpoint receives a direct GET request from the client device.

Query parameters:

- `type`: `movie`, `tv` or `anime`
- `tmdb_id`: TMDB identifier for movies/series
- `anilist_id`: AniList identifier for anime
- `season`: optional season number for TV
- `episode`: episode number; for anime POTV uses the absolute episode number

Example:

```text
GET https://example.org/potv/source?type=movie&tmdb_id=157336
```

## Response

A source returns either a JSON array or an object with a `streams` array.

```json
{
  "streams": [
    {
      "name": "Servidor 1",
      "url": "https://cdn.example.org/master.m3u8",
      "language": "es-MX",
      "quality": "1080p",
      "backend": "native",
      "headers": {
        "Referer": "https://example.org/"
      }
    }
  ]
}
```

Supported `backend` values:

- `native`: direct HLS/DASH/MP4 compatible playback
- `webview`: isolated web player
- `external`: reserved for user-selected external players

For WebView sources, `allowed_hosts` may list additional hosts that are required by the embedded player. POTV denies unsolicited navigation to hosts outside that allowlist.

```json
{
  "name": "Web player",
  "url": "https://player.example.org/embed/123",
  "backend": "webview",
  "allowed_hosts": [
    "player.example.org",
    "media.example.org"
  ]
}
```

## Security

A source must never receive POTV account credentials, subscription tokens, device identifiers or data belonging to another source. Sources only receive the media lookup parameters required for their request.

Web sources execute inside the POTV WebView isolation layer. Camera, microphone, geolocation and file access are denied by default.

## Privacy

Source URLs, responses, stream URLs, headers, cookies and user viewing history remain on the client device and are excluded from POTV telemetry.
