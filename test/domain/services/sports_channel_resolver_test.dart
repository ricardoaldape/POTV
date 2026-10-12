import 'package:flutter_test/flutter_test.dart';
import 'package:potv/domain/models/epg_program.dart';
import 'package:potv/domain/models/live_channel.dart';
import 'package:potv/domain/models/sports_event.dart';
import 'package:potv/domain/models/stream_candidate.dart';
import 'package:potv/domain/services/sports_channel_resolver.dart';

void main() {
  final time = DateTime.utc(2026, 10, 18, 19);
  final event = SportsEvent(
    id: 'match-1', sport: 'Soccer', competition: 'Liga',
    home: 'Barcelona', away: 'Real Madrid', startsAt: time,
  );
  final channel = LiveChannel(
    id: 'c1', name: 'Sports TV', epgId: 'channel-1',
    stream: StreamCandidate(
      id: 'test', label: 'fixture',
      uri: Uri.parse('https://example.org/test.m3u8'),
    ),
  );
  EpgProgram program(String title, {String? description, int offset = 0}) =>
      EpgProgram(
        channelId: 'channel-1',
        title: title,
        description: description,
        startsAt: time.add(Duration(minutes: offset - 10)),
        endsAt: time.add(Duration(minutes: offset + 140)),
      );

  test('requires a matching EPG program with both teams', () {
    const resolver = SportsChannelResolver();
    expect(resolver.resolve(event: event, channels: [channel], programs: []),
        isEmpty);
    expect(resolver.resolve(
      event: event, channels: [channel],
      programs: [program('NFL Live, sports channel')],
    ), isEmpty);
    expect(resolver.resolve(
      event: event, channels: [channel],
      programs: [program('Barcelona highlights')],
    ), isEmpty);
    expect(resolver.resolve(
      event: event, channels: [channel],
      programs: [program('Barcelona vs Real Madrid')],
    ), hasLength(1));
  });

  test('rejects programmes that are not airing at match time', () {
    const resolver = SportsChannelResolver();
    expect(resolver.resolve(
      event: event, channels: [channel],
      programs: [program('Barcelona vs Real Madrid', offset: 400)],
    ), isEmpty);
  });

  test('rejects EPG matches on the wrong channel id', () {
    const resolver = SportsChannelResolver();
    final other = EpgProgram(
      channelId: 'different-channel',
      title: 'Barcelona vs Real Madrid',
      startsAt: time, endsAt: time.add(const Duration(hours: 2)),
    );
    expect(resolver.resolve(
      event: event, channels: [channel], programs: [other],
    ), isEmpty);
  });
}
