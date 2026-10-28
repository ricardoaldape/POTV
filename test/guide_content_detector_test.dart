import 'package:flutter_test/flutter_test.dart';
import 'package:potv/data/live_tv/xmltv_parser.dart';
import 'package:potv/domain/models/epg_program.dart';
import 'package:potv/domain/models/live_channel.dart';
import 'package:potv/domain/models/sports_event.dart';
import 'package:potv/domain/models/stream_candidate.dart';
import 'package:potv/domain/services/guide_content_detector.dart';
import 'package:potv/domain/services/live_tv_organizer.dart';

LiveChannel channel(String id, String name, {String? epgId, String? group}) =>
    LiveChannel(
      id: id,
      name: name,
      epgId: epgId,
      group: group,
      stream: StreamCandidate(
        id: 'stream:$id',
        label: name,
        uri: Uri.parse('https://stream.example/$id.m3u8'),
      ),
    );

void main() {
  // XMLTV timestamps without an offset are parsed as UTC. Use the same
  // absolute instant on Windows (America/Mexico_City) and Linux (UTC).
  final now = DateTime.utc(2026, 10, 27, 20, 30);

  test('XMLTV display name resolves exact channel and exposes now/next', () {
    const xml = '''
    <tv>
      <channel id="tv-7"><display-name>Azteca 7</display-name></channel>
      <programme channel="tv-7" start="20261027200000" stop="20261027210000"><title>Película X</title></programme>
      <programme channel="tv-7" start="20261027210000" stop="20261027220000"><title>Película Y</title></programme>
    </tv>''';
    final guide = LiveTvGuide(XmlTvParser.parse(xml));
    final tv = channel('azteca', 'Azteca 7');
    expect(guide.onAir(tv, now)?.title, 'Película X');
    expect(guide.upNext(tv, now)?.title, 'Película Y');
    expect(guide.onAir(channel('other', 'Canal Otro'), now), isNull);
  });

  test('ambiguous EPG display name does not assign the wrong programme', () {
    final guide = LiveTvGuide([
      EpgProgram(
        channelId: 'provider-A',
        channelNames: const ['Canal Uno'],
        title: 'Programa A',
        startsAt: now.subtract(const Duration(minutes: 30)),
        endsAt: now.add(const Duration(minutes: 30)),
      ),
      EpgProgram(
        channelId: 'provider-B',
        channelNames: const ['Canal Uno'],
        title: 'Programa B',
        startsAt: now.subtract(const Duration(minutes: 30)),
        endsAt: now.add(const Duration(minutes: 30)),
      ),
    ]);
    expect(guide.onAir(channel('c', 'Canal Uno'), now), isNull);
    expect(guide.onAir(channel('a', 'Canal Uno', epgId: 'provider-A'), now)?.title,
        'Programa A');
  });

  test('shows channels without EPG as unknown, never invents a programme', () {
    final values = const GuideContentDetector().build(
      channels: [
        channel('news', 'Noticias Uno'),
        channel('sports', 'ESPN', group: 'Deportes'),
      ],
      programs: const [],
      events: const [],
      now: now,
    );
    expect(values, hasLength(2));
    expect(values.every((v) => !v.hasConfirmedProgramme), isTrue);
    expect(values.where((v) => v.isSports).single.channelName, 'ESPN');
  });

  test('only live sports events with an explicitly attached stream appear', () {
    SportsEvent event(String id, {required bool live, required bool streamed}) =>
        SportsEvent(
          id: id,
          sport: 'Soccer',
          competition: 'Liga MX',
          home: 'Local',
          away: 'Visitante',
          startsAt: now,
          isLive: live,
          streams: streamed
              ? [StreamCandidate(
                  id: id,
                  label: id,
                  uri: Uri.parse('https://stream.example/$id'),
                )]
              : const [],
        );
    final items = const GuideContentDetector().build(
      channels: const [],
      programs: const [],
      events: [
        event('live', live: true, streamed: true),
        event('no-stream', live: true, streamed: false),
        event('future', live: false, streamed: true),
      ],
      now: now,
    );
    expect(items, hasLength(1));
    expect(items.single.event!.id, 'live');
    expect(items.single.currentTitle, 'Local vs Visitante');
  });

  test('filters by programme title and sport without changing stream', () {
    final sports = channel('sport', 'Fox Sports', group: 'Deportes');
    final tv = channel('tv', 'Canal Películas');
    final items = const GuideContentDetector().build(
      channels: [sports, tv],
      programs: [
        EpgProgram(
          channelId: 'Canal Películas',
          title: 'La gran película',
          startsAt: now.subtract(const Duration(minutes: 30)),
          endsAt: now.add(const Duration(minutes: 30)),
        ),
      ],
      events: const [],
      now: now,
    );
    expect(const GuideContentDetector().filter(items, search: 'gran pelicula'),
        hasLength(1));
    expect(const GuideContentDetector().filter(items, sports: true).single.id,
        'sport');
    expect(const GuideContentDetector().filter(items,
        withProgrammeOnly: true).single.id, 'tv');
  });
}
