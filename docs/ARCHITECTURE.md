# POTV Architecture

POTV is a local-first Android and Android TV media client.

The POTV control plane may handle accounts, subscriptions, device authorization, releases and privacy-preserving analytics. It must not store, proxy, cache or relay audiovisual streams, playlists, addon configurations, viewing history or source credentials.

## Priority order

1. Core UI and playback
2. Live TV and EPG
3. Sports Hub
4. Local phone-to-TV sync
5. Accounts, subscriptions and updates
6. Stremio, Nuvio and progressive Kodi compatibility

## Playback

Local source -> StreamCandidate -> native player / isolated WebView / external player.

All source configuration stays on the user's device.
