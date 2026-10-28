import '../models/stream_candidate.dart';

/// Selects compatible POTV player engines before embedded web fallbacks.
///
/// Does not reclassify or extract URLs. It only orders candidates that have
/// already been classified by the authorized source resolvers. A viewer's
/// explicit nonzero initial selection is respected.
abstract final class PlaybackSourceSelector {
  static int _priority(PlaybackBackend backend) => switch (backend) {
        PlaybackBackend.native => 0,
        PlaybackBackend.webView => 1,
        PlaybackBackend.external => 2,
      };

  static List<int> prioritizedIndices(List<StreamCandidate> candidates) {
    final indices = List<int>.generate(candidates.length, (index) => index);
    // Preserve source order (and therefore the configured language and
    // quality preferences) within each playback-engine category.
    indices.sort((a, b) {
      final priority = _priority(candidates[a].backend)
          .compareTo(_priority(candidates[b].backend));
      return priority != 0 ? priority : a.compareTo(b);
    });
    return indices;
  }

  static int initialIndex(
    List<StreamCandidate> candidates, {
    int requested = 0,
  }) {
    if (candidates.isEmpty) return 0;
    // Explicit requests (e.g. a selected provider in the TV guide) still win.
    if (requested > 0 && requested < candidates.length) return requested;
    return prioritizedIndices(candidates).first;
  }

  static int? nextIndex(
    List<StreamCandidate> candidates, {
    required Set<int> alreadyTried,
  }) {
    for (final index in prioritizedIndices(candidates)) {
      if (!alreadyTried.contains(index)) return index;
    }
    return null;
  }
}
