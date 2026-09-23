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
}
