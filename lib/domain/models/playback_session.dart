import 'stream_candidate.dart';

class PlaybackContext {
  final int mediaId;
  final String mediaType;
  final String title;
  final String? externalId;
  final int? season;
  final int? episode;
  final String? poster;

  const PlaybackContext({
    required this.mediaId,
    required this.mediaType,
    required this.title,
    this.externalId,
    this.season,
    this.episode,
    this.poster,
  });

  String get historyKey {
    final parts = <String>[
      mediaType,
      mediaId.toString(),
      if (season != null) 's$season',
      if (episode != null) 'e$episode',
    ];
    return parts.join(':');
  }
}

class PlaybackSession {
  final String title;
  final List<StreamCandidate> candidates;
  final int initialIndex;
  final PlaybackContext? playbackContext;
  final bool isLive;

  const PlaybackSession({
    required this.title,
    required this.candidates,
    this.initialIndex = 0,
    this.playbackContext,
    this.isLive = false,
  });

  factory PlaybackSession.single(StreamCandidate stream) {
    return PlaybackSession(
      title: stream.label,
      candidates: [stream],
      isLive: false,
    );
  }

  StreamCandidate get initialStream {
    if (candidates.isEmpty) {
      throw StateError('PlaybackSession requires at least one stream');
    }
    final safeIndex = initialIndex.clamp(0, candidates.length - 1).toInt();
    return candidates[safeIndex];
  }
}
