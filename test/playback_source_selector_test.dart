import 'package:flutter_test/flutter_test.dart';
import 'package:potv/domain/models/stream_candidate.dart';
import 'package:potv/domain/services/playback_source_selector.dart';

StreamCandidate candidate(String id, PlaybackBackend backend) =>
    StreamCandidate(
      id: id,
      label: id,
      uri: Uri.parse('https://example.test/$id'),
      backend: backend,
    );

void main() {
  final candidates = [
    candidate('web-a', PlaybackBackend.webView),
    candidate('native-es', PlaybackBackend.native),
    candidate('web-b', PlaybackBackend.webView),
    candidate('native-en', PlaybackBackend.native),
    candidate('external', PlaybackBackend.external),
  ];

  test('POTV native is the default even if an embed arrived first', () {
    expect(PlaybackSourceSelector.initialIndex(candidates), 1);
    expect(PlaybackSourceSelector.prioritizedIndices(candidates),
        [1, 3, 0, 2, 4]);
  });

  test('automatic failover exhausts native sources before web embeds', () {
    expect(
      PlaybackSourceSelector.nextIndex(candidates, alreadyTried: {1}),
      3,
    );
    expect(
      PlaybackSourceSelector.nextIndex(candidates, alreadyTried: {1, 3}),
      0,
    );
    expect(
      PlaybackSourceSelector.nextIndex(
          candidates, alreadyTried: {1, 3, 0, 2}),
      4,
    );
    expect(
      PlaybackSourceSelector.nextIndex(
          candidates, alreadyTried: {0, 1, 2, 3, 4}),
      isNull,
    );
  });

  test('explicit nonzero source selection is preserved', () {
    expect(PlaybackSourceSelector.initialIndex(candidates, requested: 2), 2);
    expect(PlaybackSourceSelector.initialIndex(candidates, requested: 100), 1);
  });

  test('single HTML-only video still works in compatibility mode', () {
    final html = [candidate('only-html', PlaybackBackend.webView)];
    expect(PlaybackSourceSelector.initialIndex(html), 0);
    expect(PlaybackSourceSelector.nextIndex(html, alreadyTried: {0}), isNull);
  });

  test('prioritization is stable for preferred language ordering', () {
    final natives = [
      candidate('es', PlaybackBackend.native),
      candidate('en', PlaybackBackend.native),
    ];
    expect(PlaybackSourceSelector.prioritizedIndices(natives), [0, 1]);
  });
}
