import 'stream_candidate.dart';

class PlaybackSession {
  final String title;
  final List<StreamCandidate> candidates;
  final int initialIndex;

  const PlaybackSession({
    required this.title,
    required this.candidates,
    this.initialIndex = 0,
  });

  factory PlaybackSession.single(StreamCandidate stream) {
    return PlaybackSession(
      title: stream.label,
      candidates: [stream],
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
