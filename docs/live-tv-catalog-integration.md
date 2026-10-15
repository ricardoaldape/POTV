# POTV TV en vivo 2.0

## Data sources and independence

POTV combines channel data from the following **permitted** sources:

1. Partner content gateway `POTV_PARTNER_CATALOG_URL` — `channels`, `sports_channels` and `now_next` metadata. The gateway owns its API authentication/rights; POTV does **not** include NOVA billing, credentials, branding or accounts.
2. Local user-configured M3U URL playlists and imported M3U files (now multiple sources rather than one).
3. Built-in public country and sports lists maintained by POTV, as available.

The directory assigns the categories Todos, Deportes, Noticias, Cine y series, Entretenimiento, Infantil, Música, Documentales, Cultura, Estilo de vida, Internacional and Otros. Metadata from `group`, `category`, `genre` or `group_title` is used when delivered by an authorized source. Channels that have an explicit sports category also appear in Sports Hub.

Channels with matching EPG IDs or names are grouped into **one visible channel** while preserving distinct playback candidates as backups. Contradictory nonempty EPG IDs are **not** merged. Channel favorites use the original SharedPreferences storage format.

The screen shows current and next program only if corresponding EPG metadata is available. No fake schedules are shown for channels without a valid guide. The guide can come from user-provided XMLTV or the authorized partner gateway. TV search matches channel, category and current/next show titles.

## Partner catalog JSON

A normalized, server-authorized example:

```json
{
  "data": {
    "revision": "tv-2026-10-11",
    "channels": [
      {
        "id": "channel-1",
        "name": "Canal cultural",
        "category": "Cultura",
        "epg_id": "culture-1",
        "logo": "https://image.example/culture.png",
        "primary_url": "https://cdn.example/live/one.m3u8",
        "backup_urls": [
          "https://backup.example/live/one.m3u8"
        ]
      }
    ],
    "sports_channels": [],
    "now_next": [
      {
        "channel_id": "culture-1",
        "current": {
          "title": "Programa cultural",
          "starts_at": "2026-10-11T15:00:00Z",
          "ends_at": "2026-10-11T16:00:00Z"
        },
        "next": {
          "title": "El siguiente programa",
          "starts_at": "2026-10-11T16:00:00Z",
          "ends_at": "2026-10-11T17:00:00Z"
        }
      }
    ]
  }
}
```

The client refreshes the snapshot every two minutes when active; it explicitly refreshes a partner channel's entry immediately before playback to reduce stale signed URL failures. This is a **source/catalog refresh only**, not an APK code hot update.

## M3U persistence migration

Old installations stored at most one custom playlist in `live_tv_m3u_url` or `live_tv_local_path`. Version 2 reads these legacy values into `live_tv_m3u_sources_v2`, then **adds** rather than replaces URLs/files. Sources can be removed independently using *TV en vivo → Más opciones → Gestionar mis listas*. The list management view shows only hostnames, not token-bearing URLs. Imported files are given content-addressed filenames and kept under POTV app support storage.

A single unavailable/invalid remote playlist does not erase other sources. List fetches have timeouts and a per-list size limit. This feature does not upload users' private playlists to POTV servers.

## Acceptance checklist

- Verify four common types: a public channel, a user M3U channel, an authorized partner channel and a sports channel.
- Verify channel categories, searching by channel and program, favorites and 0/1/2 backup signals.
- Import two M3U lists; both remain available; delete one and verify the other persists across app restarts.
- Confirm the displayed now/next programs match real guide data.
- Partner changes a channel's primary URL / backup list / guide category; ensure POTV reflects the update without an APK reinstall.
- Test native playback, fallback, channel selection and navigation with D-pad on **Android TV hardware** as well as Android touch.
- **No production claim** until the partner API gateway and a valid user-scoped authenticated entitlement are configured and real playback is verified.

This PR is dependent on Sports Hub 2.0 and the earlier partner source PR. No changes to `main` should happen before their independent review and merged gates.
