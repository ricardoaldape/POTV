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
    expect(matches.first.program?.title, 'Tigres vs Pumas');
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
  test('rejects teams sharing only a name prefix', () {
    final starts = DateTime.utc(2026, 10, 28, 20);
    final event = SportsEvent(
      id: 'madrid-1',
      sport: 'Soccer',
      competition: 'Champions League',
      home: 'Real Madrid',
      away: 'Atletico Madrid',
      startsAt: starts,
    );
    final channel = LiveChannel(
      id: 'sports-1',
      name: 'Deportes',
      epgId: 'espn.mx',
      stream: StreamCandidate(
        id: 'stream-1',
        label: 'Deportes',
        uri: Uri.parse('https://example.com/live.m3u8'),
      ),
    );
    final program = EpgProgram(
      channelId: 'espn.mx',
      title: 'Real Sociedad vs Atletico Madrid',
      startsAt: starts,
      endsAt: starts.add(const Duration(hours: 2)),
    );
    expect(
      const SportsChannelResolver().resolve(
        event: event,
        channels: [channel],
        programs: [program],
      ),
      isEmpty,
    );
  });

  test('rejects a replay hours earlier, even if teams match', () {
    final starts = DateTime.utc(2026, 10, 28, 20);
    final event = SportsEvent(
      id: 'replay-1',
      sport: 'Soccer',
      competition: 'Liga MX',
      home: 'America',
      away: 'Monterrey',
      startsAt: starts,
    );
    final channel = LiveChannel(
      id: 'sports-2',
      name: 'Deportes',
      epgId: 'espn.mx',
      stream: StreamCandidate(
        id: 'stream-2',
        label: 'Deportes',
        uri: Uri.parse('https://example.com/live.m3u8'),
      ),
    );
    final program = EpgProgram(
      channelId: 'ESPN.MX',
      title: 'America vs Monterrey',
      startsAt: starts.subtract(const Duration(hours: 3)),
      endsAt: starts.subtract(const Duration(hours: 1)),
    );
    expect(
      const SportsChannelResolver().resolve(
        event: event,
        channels: [channel],
        programs: [program],
      ),
      isEmpty,
    );
  });

  test('links exact teams with case-insensitive EPG channel ID', () {
    final starts = DateTime.utc(2026, 10, 28, 20);
    final event = SportsEvent(
      id: 'confirmed-1',
      sport: 'Soccer',
      competition: 'Liga MX',
      home: 'America',
      away: 'Monterrey',
      startsAt: starts,
    );
    final channel = LiveChannel(
      id: 'sports-3',
      name: 'Deportes',
      epgId: 'ESPN.MX',
      stream: StreamCandidate(
        id: 'stream-3',
        label: 'Deportes',
        uri: Uri.parse('https://example.com/live.m3u8'),
      ),
    );
    final program = EpgProgram(
      channelId: 'espn.mx',
      title: 'America vs Monterrey',
      startsAt: starts.add(const Duration(minutes: 15)),
      endsAt: starts.add(const Duration(hours: 2)),
    );
    final matches = const SportsChannelResolver().resolve(
      event: event,
      channels: [channel],
      programs: [program],
    );
    expect(matches, hasLength(1));
    expect(matches.single.channel.id, 'sports-3');
  });
  test('does not assemble opponents from unrelated EPG fields', () {
    final starts = DateTime.utc(2026, 10, 28, 20);
    final event = SportsEvent(
      id: 'mixed-1',
      sport: 'Soccer',
      competition: 'Liga MX',
      home: 'America',
      away: 'Monterrey',
      startsAt: starts,
    );
    final channel = LiveChannel(
      id: 'sports-4',
      name: 'Deportes',
      epgId: 'espn.mx',
      stream: StreamCandidate(
        id: 'stream-4',
        label: 'Deportes',
        uri: Uri.parse('https://example.com/live.m3u8'),
      ),
    );
    final program = EpgProgram(
      channelId: 'espn.mx',
      title: 'America vs Tigres',
      description: 'Siguiente: Monterrey vs Pumas',
      startsAt: starts,
      endsAt: starts.add(const Duration(hours: 2)),
    );
    expect(
      const SportsChannelResolver().resolve(
        event: event,
        channels: [channel],
        programs: [program],
      ),
      isEmpty,
    );
  });

  test('requires two separate team mentions when names overlap', () {
    final starts = DateTime.utc(2026, 10, 28, 20);
    final event = SportsEvent(
      id: 'overlap-1',
      sport: 'Soccer',
      competition: 'Cup',
      home: 'New York City',
      away: 'York City',
      startsAt: starts,
    );
    final channel = LiveChannel(
      id: 'sports-overlap',
      name: 'Sports',
      epgId: 'sports.epg',
      stream: StreamCandidate(
        id: 'overlap-stream',
        label: 'Sports',
        uri: Uri.parse('https://example.com/sports.m3u8'),
      ),
    );
    EpgProgram program(String title) => EpgProgram(
      channelId: 'sports.epg',
      title: title,
      startsAt: starts,
      endsAt: starts.add(const Duration(hours: 2)),
    );
    const resolver = SportsChannelResolver();
    expect(
      resolver.resolve(
        event: event,
        channels: [channel],
        programs: [program('New York City: pre-game coverage')],
      ),
      isEmpty,
    );
    expect(
      resolver.resolve(
        event: event,
        channels: [channel],
        programs: [program('New York City vs York City')],
      ),
      hasLength(1),
    );
  });

  test('never links a replay or highlights EPG entry as live', () {
    final starts = DateTime.utc(2026, 10, 28, 20);
    final event = SportsEvent(
      id: 'replay-near-start',
      sport: 'Soccer',
      competition: 'Liga MX',
      home: 'América',
      away: 'Monterrey',
      startsAt: starts,
    );
    final channel = LiveChannel(
      id: 'sports-replay',
      name: 'Sports',
      epgId: 'sports.epg',
      stream: StreamCandidate(
        id: 'replay-stream',
        label: 'Sports',
        uri: Uri.parse('https://example.com/sports.m3u8'),
      ),
    );
    EpgProgram program(String title) => EpgProgram(
      channelId: 'sports.epg',
      title: title,
      startsAt: starts,
      endsAt: starts.add(const Duration(hours: 2)),
    );
    const resolver = SportsChannelResolver();
    for (final title in [
      'Repetición: América vs Monterrey',
      'America vs Monterrey - Highlights',
      'America vs Monterrey (diferido)',
    ]) {
      expect(
        resolver.resolve(
          event: event,
          channels: [channel],
          programs: [program(title)],
        ),
        isEmpty,
        reason: title,
      );
    }
    expect(
      resolver.resolve(
        event: event,
        channels: [channel],
        programs: [program('América vs Monterrey en vivo')],
      ),
      hasLength(1),
    );
  });
}
