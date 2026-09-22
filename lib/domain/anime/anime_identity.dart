class AnimeIdentity {
  final int anilistId;
  final int? malId;
  final int? anidbId;
  final int? tmdbId;
  final int? tvdbId;
  final List<String> aliases;

  const AnimeIdentity({
    required this.anilistId,
    this.malId,
    this.anidbId,
    this.tmdbId,
    this.tvdbId,
    this.aliases = const [],
  });
}

class AnimeEpisodeRef {
  final AnimeIdentity anime;
  final int absoluteEpisode;

  const AnimeEpisodeRef({
    required this.anime,
    required this.absoluteEpisode,
  });

  String get canonicalKey =>
      'anilist:${anime.anilistId}:episode:$absoluteEpisode';
}
