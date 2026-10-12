import 'package:flutter_test/flutter_test.dart';
import 'package:potv/domain/models/epg_program.dart';
import 'package:potv/domain/models/live_channel.dart';
import 'package:potv/domain/models/sports_event.dart';
import 'package:potv/domain/models/stream_candidate.dart';
import 'package:potv/domain/services/sports_channel_resolver.dart';

void main() {
  test('matches a sports event to local EPG and channel', () {
    final starts = DateTime.now().add(const Duration(minutes: 30));
    final event = SportsEvent(
      id: 'event-1',
      sport: 'Fútbol',
      competition: 'Liga Demo',
      home: 'Tigres',
      away: 'Pumas',
      startsAt: starts,
    );

    final channel = LiveChannel(
      id: 'sports-1',
      name: 'Canal Deportes',
      epgId: 'sports.demo',
      stream: StreamCandidate(
        id: 'stream-1',
        label: 'Canal Deportes',
        uri: Uri.parse('https://example.com/live.m3u8'),
      ),
    );

    final program = EpgProgram(
      channelId: 'sports.demo',
      title: 'Tigres vs Pumas',
      startsAt: starts,
      endsAt: starts.add(const Duration(hours: 2)),
    );

    const resolver = SportsChannelResolver();
    final matches = resolver.resolve(
      event: event,
      channels: [channel],
      programs: [program],
    );

    expect(matches, isNotEmpty);
    expect(matches.first.channel.id, 'sports-1');
    expect(matches.first.program.title, 'Tigres vs Pumas');
  });

  test('ignores weak one-token channel matches', () {
    final starts = DateTime.now().add(const Duration(minutes: 30));
    final event = SportsEvent(
      id: 'event-2',
      sport: 'Fútbol',
      competition: 'Liga Demo',
      home: 'America',
      away: 'Monterrey',
      startsAt: starts,
    );

    final channel = LiveChannel(
      id: 'weak-1',
      name: 'America TV',
      stream: StreamCandidate(
        id: 'weak-stream',
        label: 'America TV',
        uri: Uri.parse('https://example.com/weak.m3u8'),
      ),
    );

    const resolver = SportsChannelResolver();
    final matches = resolver.resolve(
      event: event,
      channels: [channel],
      programs: const [],
    );

    expect(matches, isEmpty);
  });

  test('matches sports names regardless of Spanish accents', () {
    final starts = DateTime.now().add(const Duration(minutes: 20));
    final event = SportsEvent(
      id: 'event-accent',
      sport: 'Fútbol',
      competition: 'Liga MX',
      home: 'América',
      away: 'Monterrey',
      startsAt: starts,
    );

    final channel = LiveChannel(
      id: 'mx-1',
      name: 'Canal Deportes MX',
      epgId: 'mx.sports',
      stream: StreamCandidate(
        id: 'mx-stream',
        label: 'Canal Deportes MX',
        uri: Uri.parse('https://example.com/mx.m3u8'),
      ),
    );

    final program = EpgProgram(
      channelId: 'mx.sports',
      title: 'America vs Monterrey',
      startsAt: starts,
      endsAt: starts.add(const Duration(hours: 2)),
    );

    const resolver = SportsChannelResolver();
    final matches = resolver.resolve(
      event: event,
      channels: [channel],
      programs: [program],
    );

    expect(matches, isNotEmpty);
    expect(matches.first.channel.id, 'mx-1');
  });
  test('does not match an NFL event merely because both teams share New York', () {
    final starts = DateTime.now().add(const Duration(minutes: 30));
    final event = SportsEvent(
      id: 'ny-nfl',
      sport: 'American Football',
      competition: 'NFL',
      home: 'New York Giants',
      away: 'New York Jets',
      startsAt: starts,
    );
    final channel = LiveChannel(
      id: 'unrelated',
      name: 'Sports Unrelated',
      epgId: 'unrelated.epg',
      stream: StreamCandidate(
        id: 'unrelated-stream',
        label: 'Sports',
        uri: Uri.parse('https://example.org/public-test.m3u8'),
      ),
    );
    final program = EpgProgram(
      channelId: 'unrelated.epg',
      title: 'New York Knicks vs Boston Celtics',
      startsAt: starts,
      endsAt: starts.add(const Duration(hours: 2)),
    );
    final matches = const SportsChannelResolver().resolve(
      event: event,
      channels: [channel],
      programs: [program],
    );
    expect(matches, isEmpty);
  });

  test('does match both distinctive NFL team names with correct channel EPG', () {
    final starts = DateTime.now().add(const Duration(minutes: 30));
    final event = SportsEvent(
      id: 'ny-nfl',
      sport: 'American Football',
      competition: 'NFL',
      home: 'New York Giants',
      away: 'New York Jets',
      startsAt: starts,
    );
    final channel = LiveChannel(
      id: 'nfl',
      name: 'Sports Fixture',
      epgId: 'nfl.epg',
      stream: StreamCandidate(
        id: 'fixture',
        label: 'Fixture',
        uri: Uri.parse('https://example.org/public-test.m3u8'),
      ),
    );
    final program = EpgProgram(
      channelId: 'nfl.epg',
      title: 'NY Giants vs NY Jets',
      startsAt: starts,
      endsAt: starts.add(const Duration(hours: 3)),
    );
    final matches = const SportsChannelResolver().resolve(
      event: event,
      channels: [channel],
      programs: [program],
    );
    expect(matches, hasLength(1));
  });

}
