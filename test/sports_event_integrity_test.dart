import 'package:flutter_test/flutter_test.dart';
import 'package:potv/domain/models/epg_program.dart';
import 'package:potv/domain/models/live_channel.dart';
import 'package:potv/domain/models/partner_content_snapshot.dart';
import 'package:potv/domain/models/sports_event.dart';
import 'package:potv/domain/models/stream_candidate.dart';
import 'package:potv/domain/services/sports_channel_resolver.dart';

void main() {
  final starts = DateTime(2026, 10, 11, 18);
  final event = SportsEvent(
    id: 'nfl-game',
    sport: 'American Football',
    competition: 'NFL',
    home: 'Chiefs',
    away: 'Bills',
    startsAt: starts,
  );
  final generic = LiveChannel(
    id: 'redbull',
    name: 'Red Bull TV',
    group: 'Sports',
    epgId: 'sports.generic',
    stream: StreamCandidate(
      id: 'generic',
      label: 'Red Bull TV',
      uri: Uri.parse('https://example.test/generic.m3u8'),
    ),
  );

  test('NFL schedule never receives unrelated generic sports links', () {
    final result = const SportsChannelResolver().resolve(
      event: event,
      channels: [generic],
      programs: [
        EpgProgram(
          channelId: 'sports.generic',
          title: 'Adventure sports and highlights',
          startsAt: starts,
          endsAt: starts.add(const Duration(hours: 2)),
        ),
      ],
    );
    expect(result, isEmpty);
  });

  test('both participating teams must occur on matched EPG channel', () {
    final unrelated = EpgProgram(
      channelId: 'sports.generic',
      title: 'Chiefs vs Ravens (NFL)',
      startsAt: starts,
      endsAt: starts.add(const Duration(hours: 2)),
    );
    final related = EpgProgram(
      channelId: 'sports.generic',
      title: 'Chiefs vs Bills',
      startsAt: starts,
      endsAt: starts.add(const Duration(hours: 2)),
    );
    const resolver = SportsChannelResolver();
    expect(resolver.resolve(
      event: event,
      channels: [generic],
      programs: [unrelated],
    ), isEmpty);
    final matches = resolver.resolve(
      event: event,
      channels: [generic],
      programs: [related],
    );
    expect(matches, hasLength(1));
    expect(matches.single.program?.title, 'Chiefs vs Bills');
  });

  test('partner event streams map only to event ID and valid HTTPS links', () {
    final snapshot = PartnerContentSnapshot.parse({
      'data': {
        'sports_events': [
          {
            'id': 'match-2026-1',
            'home': 'Chiefs',
            'away': 'Bills',
            'sport': 'American Football',
            'starts_at': starts.toIso8601String(),
            'streams': [
              {
                'url': 'https://video.example.test/nfl-game.m3u8',
                'language': 'es-MX',
              },
              {
                'url': 'https://video.example.test/nfl-game.m3u8',
              },
              {'url': 'http://untrusted.example/live.m3u8'},
              {'url': 'https://user:password@private.example/live.m3u8'},
              {'url': 'https://video.example.test/backup.m3u8'},
            ],
          },
          {
            'id': 'match-2026-2',
            'home': 'Red Sox',
            'away': 'Yankees',
            'starts_at': starts.toIso8601String(),
          },
        ],
      },
    });
    expect(snapshot.sportsEvents, hasLength(2));
    final first = snapshot.sportsEvents.first;
    expect(first.id, 'partner:match-2026-1');
    expect(first.streams, hasLength(2));
    expect(first.streams.first.language, 'es-MX');
    expect(first.streams.first.id, 'partner:event:match-2026-1:0');
    expect(snapshot.sportsEvents.last.streams, isEmpty);
  });
}
