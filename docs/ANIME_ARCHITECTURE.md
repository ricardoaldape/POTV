# POTV Anime Architecture

POTV treats anime as a first-class vertical rather than forcing it through the movie/TV source path.

## Canonical identity

Primary identity: AniList ID.

Optional mappings:
- MyAnimeList
- AniDB
- TMDB
- TVDB

Canonical episode key:

```text
AniList ID + absolute episode number
```

This avoids coupling episode matching to provider-specific season numbering.

## Resolution pipeline

```text
AniList metadata
  -> ID mappings and aliases
  -> title normalization
  -> provider series matching
  -> episode canonicalization
  -> provider episode lookup
  -> resolver
  -> health check
  -> StreamCandidate[]
  -> POTV player
```

## Adapter contract

Each anime source adapter implements:

```text
searchSeries()
episodes()
resolveEpisode()
healthCheck()
```

Adapters never control POTV UI. They only return normalized results.

## Planned provider adapters

The integration work prepared in the parallel POTV anime track targets adapters for:
- JKAnime
- AnimeFLV
- TioAnime
- AnimeAV1
- AnimoraTV
- VerAnimes
- OtakusTV2

These adapters remain client-side/local-first. POTV servers do not store provider URLs, resolved streams, cookies, source configuration or viewing history.

## UX rule

Anime follows the same product rule as movies and series:

```text
one title card
  -> one canonical episode
  -> multiple candidates hidden behind one Play action
```

The user should not need to choose a provider before playback. POTV ranks healthy candidates and exposes manual server switching only inside the player when needed.

## Next integration step

Wire the existing anime provider work into the `AnimeSourceAdapter` contract and add AniList-backed Anime discovery as a third home category beside Movies and Series.
