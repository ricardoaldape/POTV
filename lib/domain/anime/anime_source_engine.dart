import '../models/stream_candidate.dart';
import 'anime_identity.dart';
import 'anime_source_adapter.dart';

class AnimeResolutionResult {
  final List<StreamCandidate> candidates;
  final int adaptersQueried;
  final int adaptersHealthy;

  const AnimeResolutionResult({
    required this.candidates,
    required this.adaptersQueried,
    required this.adaptersHealthy,
  });
}

class AnimeSourceEngine {
  final List<AnimeSourceAdapter> adapters;

  const AnimeSourceEngine(this.adapters);

  Future<AnimeResolutionResult> resolve(
    AnimeEpisodeRef episode,
  ) async {
    final candidates = <StreamCandidate>[];
    var healthy = 0;

    for (final adapter in adapters) {
      if (!await adapter.healthCheck()) continue;
      healthy++;

      final seriesMatches = await adapter.searchSeries(episode.anime);
      if (seriesMatches.isEmpty) continue;

      final series = [...seriesMatches]
        ..sort((a, b) => b.confidence.compareTo(a.confidence));

      final episodes = await adapter.episodes(series.first);
      AnimeEpisodeMatch? providerEpisode;
      for (final item in episodes) {
        if (item.absoluteEpisode == episode.absoluteEpisode) {
          providerEpisode = item;
          break;
        }
      }

      if (providerEpisode == null) continue;
      candidates.addAll(
        await adapter.resolveEpisode(episode, providerEpisode),
      );
    }

    return AnimeResolutionResult(
      candidates: candidates,
      adaptersQueried: adapters.length,
      adaptersHealthy: healthy,
    );
  }
}
