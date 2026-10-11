import 'package:flutter_test/flutter_test.dart';
import 'package:potv/domain/models/epg_program.dart';
import 'package:potv/domain/models/live_channel.dart';
import 'package:potv/domain/models/partner_content_snapshot.dart';
import 'package:potv/domain/models/stream_candidate.dart';
import 'package:potv/domain/services/live_tv_organizer.dart';

LiveChannel makeChannel(String name, {
  String group = '',
  String? epg,
  String? link,
  List<StreamCandidate> backups = const [],
}) => LiveChannel(
      id: 'source:$name:${link ?? "one"}',
      name: name,
      group: group,
      epgId: epg,
      stream: StreamCandidate(
        id: 'stream:$name',
        label: name,
        uri: Uri.parse(link ?? 'https://stream.example/${Uri.encodeComponent(name)}'),
      ),
      backupStreams: backups,
    );

void main() {
  const organizer = LiveTvOrganizer();

  test('classifies sports, news, kids, films, culture and documentary feeds', () {
    final cases = <String, LiveTvCategory>{
      'Deportes': LiveTvCategory.sports,
      'Noticias': LiveTvCategory.news,
      'Cine y series': LiveTvCategory.movies,
      'Infantil': LiveTvCategory.kids,
      'Música': LiveTvCategory.music,
      'Cultura': LiveTvCategory.culture,
      'Documentales': LiveTvCategory.documentary,
      'Entretenimiento': LiveTvCategory.entertainment,
      'Internacional': LiveTvCategory.international,
      'Más canales': LiveTvCategory.other,
    };
    for (final entry in cases.entries) {
      expect(organizer.categoryFor(makeChannel('Canal TV', group: entry.key)),
          entry.value, reason: entry.key);
    }
    expect(
      organizer.categoryFor(makeChannel('NFL Network', group: 'Televisión')),
      LiveTvCategory.sports,
    );
    expect(
      organizer.categoryFor(makeChannel('ESPN', group: 'Canales')),
      LiveTvCategory.sports,
    );
    expect(
      organizer.categoryFor(makeChannel('Canal 22', group: 'México · Cultura')),
      LiveTvCategory.culture,
    );
  });

  test('merges partner, local M3U and sports streams with distinct backups', () {
    final merged = organizer.merge(
      partner: [makeChannel('Canal Uno', group: 'Noticias', epg: 'canal1',
        link: 'https://partner.example/primary.m3u8')],
      local: [
        makeChannel('Canal Uno', group: 'News', epg: 'canal1',
          link: 'https://user.example/fallback.m3u8'),
        makeChannel('Canal Dos', group: 'Cine'),
      ],
      partnerSports: [makeChannel('Canal Deportes', group: 'Deportes')],
      publicSports: [makeChannel('Canal Uno', group: 'Noticias', epg: 'canal1',
        link: 'https://user.example/fallback.m3u8')],
    );
    expect(merged, hasLength(3));
    final first = merged.first;
    expect(first.name, 'Canal Uno');
    expect(first.stream.uri.host, 'partner.example');
    expect(first.playbackCandidates, hasLength(2));
    expect(first.playbackCandidates.last.uri.host, 'user.example');
    expect(organizer.counts(merged)[LiveTvCategory.sports], 1);
    expect(organizer.counts(merged)[LiveTvCategory.news], 1);
  });

  test('sports-only provider feed is identified even with a generic name', () {
    final merged = organizer.merge(
      partner: [makeChannel('Channel X', group: 'General', epg: 'sport-1')],
      local: const [],
      partnerSports: [makeChannel('Channel X', group: 'General', epg: 'sport-1',
        link: 'https://sport.example/stream')],
      publicSports: [makeChannel('Special Feed', group: 'General')],
    );
    expect(merged, hasLength(2));
    expect(organizer.categoryFor(merged.first), LiveTvCategory.sports);
    expect(merged.first.playbackCandidates, hasLength(2));
    expect(organizer.categoryFor(merged.last), LiveTvCategory.sports);
  });

  test('conflicting explicit guide IDs do not silently combine channels', () {
    final merged = organizer.merge(
      partner: [makeChannel('Canal 1', epg: 'mx-a')],
      local: [makeChannel('Canal 1', epg: 'us-b')],
      partnerSports: const [],
      publicSports: const [],
    );
    expect(merged, hasLength(2));
  });

  test('guide matches EPG id and gives on-air and next programmes', () {
    final now = DateTime(2026, 10, 11, 20);
    final guide = LiveTvGuide([
      EpgProgram(
        channelId: 'tv-news',
        title: 'Noticias de hoy',
        startsAt: now.subtract(const Duration(minutes: 20)),
        endsAt: now.add(const Duration(minutes: 10)),
      ),
      EpgProgram(
        channelId: 'tv-news',
        title: 'Resumen nocturno',
        startsAt: now.add(const Duration(minutes: 10)),
        endsAt: now.add(const Duration(minutes: 50)),
      ),
    ]);
    final channel = makeChannel('Noticias Mexicanas', epg: 'TV-NEWS');
    expect(guide.onAir(channel, now)?.title, 'Noticias de hoy');
    expect(guide.upNext(channel, now)?.title, 'Resumen nocturno');
    final result = organizer.filter([channel],
      category: LiveTvCategory.news,
      search: 'RESUMEN',
      favorites: const {},
      favoritesOnly: false,
      guide: guide,
      now: now);
    expect(result, hasLength(1));
    final noMatch = organizer.filter([channel],
      category: LiveTvCategory.sports,
      search: '',
      favorites: const {},
      favoritesOnly: false,
      guide: guide,
      now: now);
    expect(noMatch, isEmpty);
  });

  test('favorites remain visible by EPG or old name key after a merge', () {
    final merged = organizer.merge(
      partner: [makeChannel('News TV', group: 'Noticias', epg: 'partner-news')],
      local: [makeChannel('News TV', group: 'Noticias', epg: 'partner-news')],
      partnerSports: const [],
      publicSports: const [],
    );
    final favorites = <String>{'name:news tv'};
    final filtered = organizer.filter(merged,
      category: LiveTvCategory.all,
      search: '',
      favorites: favorites,
      favoritesOnly: true,
      guide: LiveTvGuide(const []),
      now: DateTime.now());
    expect(filtered, hasLength(1));
  });

  test('partner catalog can refresh channel category and now/next guide', () {
    final now = DateTime.now().toUtc();
    final snapshot = PartnerContentSnapshot.parse({
      'revision': 'tv-revision-2',
      'channels': [
        {
          'id': 'one',
          'name': 'Noticiero Uno',
          'category': 'Noticias',
          'epg_id': 'partner-epg',
          'primary_url': 'https://cdn.example/primary.m3u8',
          'backup_urls': ['https://cdn.example/backup.m3u8'],
        }
      ],
      'now_next': [
        {
          'channel_id': 'partner-epg',
          'current': {
            'title': 'En vivo: Noticias',
            'starts_at': now.subtract(const Duration(minutes: 5))
                .toIso8601String(),
            'ends_at': now.add(const Duration(minutes: 25))
                .toIso8601String(),
          },
          'next': {
            'title': 'Entrevistas',
            'starts_at': now.add(const Duration(minutes: 25))
                .toIso8601String(),
            'ends_at': now.add(const Duration(minutes: 55))
                .toIso8601String(),
          }
        }
      ]
    });
    final channel = snapshot.channels.single;
    expect(channel.group, 'Noticias');
    expect(channel.playbackCandidates, hasLength(2));
    expect(snapshot.guidePrograms, hasLength(2));
    final guide = LiveTvGuide(snapshot.guidePrograms);
    expect(guide.onAir(channel, DateTime.now())?.title, 'En vivo: Noticias');
    expect(guide.upNext(channel, DateTime.now())?.title, 'Entrevistas');
  });
}
