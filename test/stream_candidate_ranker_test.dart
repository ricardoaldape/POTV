import 'package:flutter_test/flutter_test.dart';
import 'package:potv/domain/models/stream_candidate.dart';
import 'package:potv/domain/services/stream_candidate_ranker.dart';

void main() {
  const ranker = StreamCandidateRanker();

  test('prefers native Spanish 1080p over weaker candidates', () {
    final ranked = ranker.rank([
      StreamCandidate(
        id: 'web',
        label: 'Server Web 4K',
        uri: Uri.parse('https://example.com/embed'),
        quality: '4K',
        backend: PlaybackBackend.webView,
      ),
      StreamCandidate(
        id: 'native-en',
        label: 'English',
        uri: Uri.parse('https://example.com/en.m3u8'),
        language: 'en',
        quality: '1080p',
      ),
      StreamCandidate(
        id: 'native-es',
        label: 'Latino',
        uri: Uri.parse('https://example.com/es.m3u8'),
        language: 'es-MX',
        quality: '1080p',
      ),
    ]);

    expect(ranked.first.id, 'native-es');
  });

  test('deduplicates identical playback candidates', () {
    final ranked = ranker.rank([
      StreamCandidate(
        id: 'a',
        label: 'A',
        uri: Uri.parse('https://example.com/video.m3u8'),
        language: 'es',
      ),
      StreamCandidate(
        id: 'b',
        label: 'B',
        uri: Uri.parse('https://example.com/video.m3u8'),
        language: 'es',
      ),
    ]);

    expect(ranked, hasLength(1));
  });
  test('a Spanish 4K HTML page never outranks a native 480p video', () {
    final sorted = ranker.rank([
      StreamCandidate(
        id: 'html',
        label: 'Latino 4K',
        uri: Uri.parse('https://html.example.test/embed'),
        language: 'es-MX',
        quality: '2160p',
        backend: PlaybackBackend.webView,
      ),
      StreamCandidate(
        id: 'native',
        label: 'Original 480p',
        uri: Uri.parse('https://cdn.example.test/file.mp4'),
        language: 'en',
        quality: '480p',
      ),
    ]);
    expect(sorted.first.id, 'native');
    expect(sorted.last.id, 'html');
  });

}
