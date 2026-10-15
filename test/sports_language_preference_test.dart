import 'package:flutter_test/flutter_test.dart';
import 'package:potv/data/live_tv/m3u_parser.dart';
import 'package:potv/domain/models/live_channel.dart';
import 'package:potv/domain/models/stream_candidate.dart';
import 'package:potv/domain/services/sports_channel_language.dart';

LiveChannel _channel(String id, {String? language, List<StreamCandidate> backups = const []}) {
  return LiveChannel(
    id: id,
    name: 'Canal $id',
    group: 'Deportes',
    stream: StreamCandidate(
      id: '$id:main',
      label: id,
      uri: Uri.parse('https://example.org/$id.m3u8'),
      language: language,
    ),
    backupStreams: backups,
  );
}

void main() {
  const service = SportsChannelLanguage();

  test('M3U conserves tvg-language without guessing narration from country', () {
    const playlist = '#EXTM3U\n'
        '#EXTINF:-1 tvg-name="Latino" group-title="Sports" tvg-language="spa",Latino\n'
        'https://example.org/es.m3u8\n'
        '#EXTINF:-1 tvg-name="English" group-title="Sports" tvg-language="eng",English\n'
        'https://example.org/en.m3u8\n'
        '#EXTINF:-1 tvg-name="Unknown" group-title="México",Unknown\n'
        'https://example.org/no-language.m3u8\n'
        '#EXTINF:-1 tvg-name="Both" tvg-language="spa;eng",Both\n'
        'https://example.org/both.m3u8\n';
    final channels = M3uParser.parse(playlist);
    expect(channels, hasLength(4));
    expect(channels[0].stream.language, 'spa');
    expect(channels[1].stream.language, 'eng');
    expect(channels[2].stream.language, isNull);
    expect(channels[3].stream.language, 'spa;eng');
    expect(service.languages(channels[3]), {'es', 'en'});
  });

  test('ES/EN preference preserves unknown and bilingual entries', () {
    final spanish = _channel('es', language: 'es-MX');
    final english = _channel('en', language: 'en-US');
    final unknown = _channel('unknown');
    final bilingual = _channel('both', language: 'spa;eng');
    final all = [english, unknown, spanish, bilingual];

    final es = service.preferredChannels(all, SportsLanguagePreference.spanish);
    expect(es.map((c) => c.id), ['es', 'both', 'unknown']);
    final en = service.preferredChannels(all, SportsLanguagePreference.english);
    expect(en.map((c) => c.id), ['en', 'both', 'unknown']);
    expect(service.preferredChannels(all, SportsLanguagePreference.all), all);
    expect(service.labelFor(unknown), isNull);
    expect(service.labelFor(bilingual), 'ES / EN');
    expect(service.tags('português; ruso'), isEmpty);
    expect(service.tags('español / English'), {'es','en'});
  });

  test('Spanish playback starts with Spanish backup and keeps all alternatives', () {
    final channel = _channel(
      'bilingual',
      language: 'eng',
      backups: [
        StreamCandidate(
          id: 'es',
          label: 'ES',
          language: 'spa',
          uri: Uri.parse('https://es.example/live.m3u8'),
        ),
        StreamCandidate(
          id: 'unknown',
          label: 'Unknown',
          uri: Uri.parse('https://other.example/live.m3u8'),
        ),
      ],
    );
    expect(service.orderedStreams(channel, SportsLanguagePreference.spanish)
        .map((s) => s.id), ['es', 'unknown', 'bilingual:main']);
    expect(service.orderedStreams(channel, SportsLanguagePreference.english)
        .map((s) => s.id), ['bilingual:main','unknown','es']);
    expect(service.orderedStreams(channel, SportsLanguagePreference.all)
        .map((s) => s.id), ['bilingual:main','es','unknown']);
  });
}
