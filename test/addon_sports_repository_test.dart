import 'package:flutter_test/flutter_test.dart';
import 'package:potv/data/addons/stremio_protocol.dart';
import 'package:potv/data/sports/addon_sports_protocol.dart';
import 'package:potv/domain/models/stremio_addon_config.dart';

void main() {
  const addon = StremioAddonConfig(
    id: 'sports.test',
    name: 'Sports Test',
    manifestUri: Uri.parse('https://addon.example/manifest.json'),
  );

  test('parses live sports catalog items', () {
    final items = AddonSportsProtocol.parseCatalog(
      addon: addon,
      fallbackType: 'tv',
      raw: {
        'metas': [
          {
            'id': 'event-1',
            'type': 'tv',
            'name': '🔴 LIVE: Team A vs Team B',
            'genres': ['Football'],
            'description': 'LIVE NOW',
            'poster': 'https://example.com/poster.jpg',
          }
        ],
      },
    );

    expect(items, hasLength(1));
    expect(items.first.name, contains('Team A'));
    expect(items.first.genre, 'Football');
    expect(items.first.isLive, isTrue);
    expect(items.first.poster.toString(), 'https://example.com/poster.jpg');
  });

  test('parses direct playback candidates returned by sports addon', () {
    final streams = StremioProtocol.parseStreams(
      addon: addon,
      raw: {
        'streams': [
          {
            'name': 'Latino 1080p',
            'url': 'https://example.com/live.m3u8',
          }
        ],
      },
    );

    expect(streams, hasLength(1));
    expect(streams.first.uri.toString(), 'https://example.com/live.m3u8');
    expect(streams.first.language, 'es-MX');
    expect(streams.first.quality, '1080p');
  });

  test('builds sports stream URL from addon manifest', () {
    final uri = StremioProtocol.streamUri(
      addon: addon,
      type: 'tv',
      itemId: 'event-1',
    );

    expect(
      uri.toString(),
      'https://addon.example/stream/tv/event-1.json',
    );
  });
}
