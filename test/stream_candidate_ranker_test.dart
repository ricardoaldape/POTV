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

  test('scores Latino dual-audio 1080p above foreign-language 4K', () {
    final latino = StreamCandidate(
      id: 'latino',
      label: 'Movie Latino Dual-Audio 1080p',
      uri: Uri.parse('https://example.com/movie.latino.dual-audio.1080p.mkv'),
      language: 'es-MX',
    );
    final foreign = StreamCandidate(
      id: 'foreign',
      label: 'Movie French 4K',
      uri: Uri.parse('https://example.com/movie.fr-fr.4k.mkv'),
      language: 'fr-FR',
    );

    expect(ranker.score(latino), greaterThan(ranker.score(foreign)));
    expect(ranker.analyze(latino).reasons, contains('audio/español +100'));
    expect(ranker.analyze(latino).reasons, contains('multi audio/subs +50'));
  });

  test('adds subtitle bonus when Spanish subtitles are available', () {
    final candidate = StreamCandidate(
      id: 'subs',
      label: 'English 1080p',
      uri: Uri.parse('https://example.com/movie.en.1080p.mkv'),
      language: 'en',
      subtitles: [
        ExternalSubtitleTrack(
          uri: Uri.parse('https://example.com/subtitles.es.vtt'),
          language: 'es',
        ),
      ],
    );

    expect(ranker.analyze(candidate).reasons, contains('subtítulos ES +10'));
  });

}
