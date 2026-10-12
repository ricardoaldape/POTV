import '../../domain/models/series_episode.dart';

/// Select a genuinely catalogued next episode, never invent an episode number.
class NextEpisodeSelector {
  const NextEpisodeSelector._();

  static SeriesEpisode? next(
    List<SeriesEpisode> episodes, {
    required int season,
    required int episode,
    DateTime? now,
  }) {
    final known = [...episodes]..sort((a, b) {
      final bySeason = a.season.compareTo(b.season);
      if (bySeason != 0) return bySeason;
      return a.episode.compareTo(b.episode);
    });
    final today = (now ?? DateTime.now()).toUtc();
    for (final candidate in known) {
      if (candidate.season < season ||
          (candidate.season == season && candidate.episode <= episode)) {
        continue;
      }
      if (candidate.releasedAt != null &&
          candidate.releasedAt!.toUtc().isAfter(today)) {
        return null;
      }
      return candidate;
    }
    return null;
  }
}
