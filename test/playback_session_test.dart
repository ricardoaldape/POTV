import 'package:flutter_test/flutter_test.dart';
import 'package:potv/domain/models/playback_session.dart';
import 'package:potv/domain/models/stream_candidate.dart';

void main() {
  final stream = StreamCandidate(
    id: 'demo',
    label: 'Demo',
    uri: Uri.parse('https://example.test/video.m3u8'),
  );

  test('single playback session is VOD by default', () {
    final session = PlaybackSession.single(stream);
    expect(session.isLive, isFalse);
  });

  test('live playback session must be explicit', () {
    final session = PlaybackSession(
      title: 'Live',
      candidates: [stream],
      isLive: true,
    );
    expect(session.isLive, isTrue);
  });
  test('episode queues are optional and keep the same playback surface', () {
    const current = PlaybackContext(
      mediaId: 7, mediaType: 'tv', title: 'POTV Series',
      season: 2, episode: 3,
    );
    const before = PlaybackContext(
      mediaId: 7, mediaType: 'tv', title: 'POTV Series',
      season: 2, episode: 2,
    );
    const after = PlaybackContext(
      mediaId: 7, mediaType: 'tv', title: 'POTV Series',
      season: 2, episode: 4,
    );
    final session = PlaybackSession(
      title: 'POTV Series', candidates: [stream], playbackContext: current,
      previousQueue: const [before], autoplayQueue: const [after],
    );
    expect(session.previousQueue.single.episode, 2);
    expect(session.autoplayQueue.single.episode, 4);
    expect(session.playbackContext?.historyKey, 'tv:7:s2:e3');
  });

}
