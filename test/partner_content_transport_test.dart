import 'package:flutter_test/flutter_test.dart';
import 'package:potv/domain/models/partner_content_snapshot.dart';

void main() {
  test('normalizes gateway Xtream aliases with HLS and DASH', () {
    final snapshot = PartnerContentSnapshot.parse({
      'data': {
        'revision': 'transport-1',
        'xtream_channels': [
          {
            'id': 'mx-1',
            'name': 'Canal MX',
            'group': 'Noticias',
            'epg_id': 'mx.news',
            'hls_url': 'https://media.example/live/mx-1.m3u8',
            'backups': [
              {
                'dash_url': 'https://backup.example/live/mx-1.mpd',
                'language': 'es-419',
              }
            ],
          }
        ],
        'xtream_sports_channels': [
          {
            'id': 'sports-1',
            'name': 'POTV Sports',
            'group': 'Deportes',
            'dash_url': 'https://media.example/live/sports-1.mpd',
          }
        ],
      }
    });

    expect(snapshot.channels, hasLength(1));
    expect(snapshot.channels.single.stream.uri.path, endsWith('.m3u8'));
    expect(snapshot.channels.single.backupStreams, hasLength(1));
    expect(
      snapshot.channels.single.backupStreams.single.uri.path,
      endsWith('.mpd'),
    );
    expect(snapshot.sportsChannels, hasLength(1));
    expect(snapshot.sportsChannels.single.stream.uri.path, endsWith('.mpd'));
  });

  test('authorized partner catalog accepts licensed premium channel names', () {
    final snapshot = PartnerContentSnapshot.parse({
      'data': {
        'revision': 'licensed-1',
        'channels': [
          {
            'id': 'licensed-espn',
            'name': 'ESPN',
            'group': 'Deportes',
            'hls_url': 'https://licensed.example/live/espn.m3u8',
          },
          {
            'id': 'licensed-hbo',
            'name': 'HBO',
            'group': 'Cine y series',
            'hls_url': 'https://licensed.example/live/hbo.m3u8',
          },
        ],
      }
    });

    expect(snapshot.channels.map((item) => item.name), containsAll(['ESPN', 'HBO']));
    expect(
      snapshot.channels.every((item) => item.id.startsWith('partner:tv:')),
      isTrue,
    );
  });

  test('sports event keeps only streams attached to that event', () {
    final snapshot = PartnerContentSnapshot.parse({
      'data': {
        'sports_events': [
          {
            'id': 'nfl-1',
            'sport': 'American Football',
            'competition': 'NFL',
            'home': 'Home',
            'away': 'Away',
            'starts_at': '2026-10-12T20:00:00Z',
            'streams': [
              {
                'hls_url': 'https://media.example/events/nfl-1.m3u8',
                'language': 'es-419',
              },
            ],
          },
          {
            'id': 'nfl-2',
            'sport': 'American Football',
            'competition': 'NFL',
            'home': 'Other Home',
            'away': 'Other Away',
            'starts_at': '2026-10-12T22:00:00Z',
          },
        ],
      }
    });

    expect(snapshot.sportsEvents, hasLength(2));
    expect(snapshot.sportsEvents.first.streams, hasLength(1));
    expect(
      snapshot.sportsEvents.first.streams.single.uri.path,
      contains('/events/nfl-1.m3u8'),
    );
    expect(snapshot.sportsEvents.last.streams, isEmpty);
  });
}
