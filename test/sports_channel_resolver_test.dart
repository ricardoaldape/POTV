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
}
