import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:potv/data/history/stream_server_health_repository.dart';
import 'package:potv/domain/models/stream_candidate.dart';

StreamCandidate _server(String id, String url) => StreamCandidate(
      id: id,
      label: 'Server $id',
      uri: Uri.parse(url),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  const store = StreamServerHealthRepository();

  test('last working source wins within the same title for 3 hours', () async {
    final a = _server('first', 'https://cdn1.example/video.m3u8');
    final b = _server('backup', 'https://cdn2.example/film?token=secret');
    await store.reportPlaying('movie:101', b);
    expect((await store.rankFor('movie:101', [a, b])).first.id, 'backup');
    expect((await store.rankFor('movie:102', [a, b])).first.id, 'first');
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('potv_playback_server_health_v1')!;
    expect(raw, isNot(contains('secret')));
    expect(raw, isNot(contains('cdn2.example')));
    expect(raw, isNot(contains('movie:101')));
  });

  test('repeated failures move an unreliable stream behind healthy alternative',
      () async {
    final a = _server('failing', 'https://cdn1.example/movie');
    final b = _server('healthy', 'https://cdn2.example/movie');
    await store.reportPlaying('tv:2:s1:e3', a);
    for (var i = 0; i < 3; i++) {
      await store.reportError('tv:2:s1:e3', a);
    }
    final candidates = await store.rankFor('tv:2:s1:e3', [a, b]);
    expect(candidates.first.id, b.id);
    await store.reportPlaying('tv:2:s1:e3', a);
    expect((await store.rankFor('tv:2:s1:e3', [a, b])).first.id, a.id);
  });

  test('prefers ad-free native playback over previously used embedded page',
      () async {
    final direct = _server('native', 'https://cdn.example/live.m3u8');
    final embed = StreamCandidate(
      id: 'embed',
      label: 'Embedded player',
      backend: PlaybackBackend.webView,
      uri: Uri.parse('https://embed.example/player'),
    );
    await store.reportPlaying('movie:embedded', embed);
    expect((await store.rankFor('movie:embedded', [embed, direct]))
        .first.id, 'native');
    await store.reportError('movie:embedded', direct);
    await store.reportError('movie:embedded', direct);
    expect((await store.rankFor('movie:embedded', [direct, embed]))
        .first.id, 'embed');
  });

  test('corrupt previous health is ignored', () async {
    SharedPreferences.setMockInitialValues({
      'potv_playback_server_health_v1': 'oops',
    });
    final a = _server('original', 'https://cdn.example/test.mp4');
    expect((await store.rankFor('movie:9', [a])).single.id, a.id);
    await store.reportPlaying('movie:9', a);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('potv_playback_server_health_v1'), isNot('oops'));
  });
}
