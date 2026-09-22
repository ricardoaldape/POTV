# POTV Resolver Protocol v2

POTV resolves media through a local Provider Registry. Every resolver receives the same normalized identity and returns zero or more playback candidates. The Source Aggregator queries eligible resolvers in parallel, isolates failures, caches results briefly, ranks candidates, probes supported streams and hands the ordered list to the player.

## Request

A configured resolver endpoint receives a direct GET request from the client device.

Query parameters:

- `type`: `movie`, `tv` or `anime`
- `tmdb_id`: TMDB identifier for movies/series
- `anilist_id`: AniList identifier for anime
- `external_id`: optional IMDb or other canonical external identifier
- `title`: optional display title
- `year`: optional release/start year
- `season`: season number for episodic TV when known
- `episode`: episode number; anime uses the absolute episode number at the public resolver boundary

Examples:

```text
GET https://resolver.example/resolve?type=movie&tmdb_id=157336&external_id=tt0816692
GET https://resolver.example/resolve?type=tv&tmdb_id=1399&season=2&episode=4
GET https://resolver.example/resolve?type=anime&anilist_id=20&episode=53
```

Anime identity conversion (for example AniList absolute episode to IMDb + season/episode) happens inside POTV when a downstream provider requires series-style identifiers.

## Response

Preferred response:

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
        "Referer": "https://resolver.example/"
      }
    }
  ]
}
```

For compatibility, POTV also accepts:

- a bare JSON array;
- `results` instead of `streams`;
- `servidores` instead of `streams`;
- `servidor_url`, `resolved_m3u8` or `stream_url` instead of `url`;
- `servidor_nombre` or `server` instead of `name`;
- `idioma` / `calidad` instead of `language` / `quality`.

## Playback backend

Supported `backend` values:

- `native`: direct HLS/DASH/MP4-compatible playback;
- `webview`: isolated in-app web player;
- `external`: external application/browser.

For movie, TV and anime Play, POTV only accepts candidates that remain inside POTV (`native` or `webview`). External candidates are not used automatically.

If `backend` is omitted, POTV classifies obvious media URLs such as `.m3u8`, `.mp4`, `.m4v`, `.webm` and manifest URLs as `native`; other HTTP(S) URLs default to the isolated WebView backend.

For WebView candidates, `allowed_hosts` can list additional hosts required by the embedded player.

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

## Provider Registry

Build-time resolvers can be registered with `POTV_RESOLVER_ENDPOINTS_JSON`.

```json
[
  {
    "id": "resolver-a",
    "name": "Resolver A",
    "endpoint": "https://resolver-a.example/resolve",
    "media_types": ["movie", "tv"],
    "priority": 20
  },
  {
    "id": "resolver-anime",
    "name": "Resolver Anime",
    "endpoint": "https://anime.example/resolve",
    "media_types": ["anime"],
    "priority": 30
  }
]
```

Lower priority values are queried first in registry order, although eligible resolvers execute concurrently.

## Reliability

Each resolver is isolated. A synchronous exception, asynchronous exception or timeout from one provider cannot abort the other providers. Identical media/episode requests are deduplicated while in flight and successful aggregate results are cached briefly on-device.

The player receives an ordered candidate list and performs automatic failover when a native stream fails.

## Security and privacy

Resolvers never receive POTV account credentials, subscription tokens, device identifiers or data belonging to another provider. They receive only the normalized media lookup parameters required for resolution.

Web candidates execute inside POTV's isolated WebView layer. Source responses, stream URLs, headers and viewing history stay on the client device and are excluded from POTV telemetry.
