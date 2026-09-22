import '../models/stream_candidate.dart';
import 'anime_identity.dart';

class AnimeSeriesMatch {
  final String providerSeriesId;
  final String title;
  final double confidence;

  const AnimeSeriesMatch({
    required this.providerSeriesId,
    required this.title,
    required this.confidence,
  });
}

class AnimeEpisodeMatch {
  final String providerEpisodeId;
  final int absoluteEpisode;
  final Set<String> languages;

  const AnimeEpisodeMatch({
    required this.providerEpisodeId,
    required this.absoluteEpisode,
    this.languages = const {},
  });
}

abstract interface class AnimeSourceAdapter {
  String get id;
  String get displayName;

  Future<List<AnimeSeriesMatch>> searchSeries(
    AnimeIdentity anime,
  );

  Future<List<AnimeEpisodeMatch>> episodes(
    AnimeSeriesMatch series,
  );

  Future<List<StreamCandidate>> resolveEpisode(
    AnimeEpisodeRef episode,
    AnimeEpisodeMatch providerEpisode,
  );

  Future<bool> healthCheck();
}
