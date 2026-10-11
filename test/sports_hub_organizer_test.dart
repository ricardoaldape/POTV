import 'package:flutter_test/flutter_test.dart';
import 'package:potv/domain/models/live_channel.dart';
import 'package:potv/domain/models/sports_event.dart';
import 'package:potv/domain/models/stream_candidate.dart';
import 'package:potv/domain/services/sports_hub_organizer.dart';

LiveChannel channel(
  String name, {
  String group = '',
  String? epgId,
  String? sourceId,
  String? streamUrl,
}) =>
    LiveChannel(
      id: sourceId ?? name,
      name: name,
      group: group,
      epgId: epgId,
      stream: StreamCandidate(
        id: sourceId ?? name,
        label: name,
        uri: Uri.parse(streamUrl ??
            'https://stream.example/${Uri.encodeComponent(name)}.m3u8'),
      ),
    );

SportsEvent game({
  required String id,
  required String sport,
  String competition = '',
  int hour = 14,
  bool live = false,
}) =>
    SportsEvent(
      id: id,
      sport: sport,
      competition: competition,
      home: 'Home',
      away: 'Away',
      startsAt: DateTime(2026, 10, 11, hour),
      isLive: live,
    );

void main() {
  const organizer = SportsHubOrganizer();
  group('Sports Hub taxonomy', () {
    test('American football is never classified as soccer', () {
      expect(organizer.classifySport('American Football'),
          SportsHubCategory.americanFootball);
      expect(organizer.classifySport('Fútbol americano - NFL'),
          SportsHubCategory.americanFootball);
      expect(organizer.classifySport('Soccer - Liga MX'),
          SportsHubCategory.soccer);
      expect(organizer.classifySport('Fútbol'), SportsHubCategory.soccer);
      expect(organizer.classifySport('Football'), SportsHubCategory.soccer);
    });

    test('fighting, boxing, UFC and wrestling share combat category', () {
      for (final name in ['UFC', 'MMA', 'Boxeo', 'WWE wrestling', 'Kickboxing']) {
        expect(organizer.classifySport(name), SportsHubCategory.combat,
            reason: name);
      }
    });

    test('baseball, basketball, hockey, motor, tennis and unknown sport', () {
      expect(organizer.classifySport('NBA Basketball'),
          SportsHubCategory.basketball);
      expect(organizer.classifySport('Béisbol MLB'),
          SportsHubCategory.baseball);
      expect(organizer.classifySport('Ice Hockey NHL'),
          SportsHubCategory.hockey);
      expect(organizer.classifySport('Formula 1'), SportsHubCategory.motorsport);
      expect(organizer.classifySport('Tenis ATP'), SportsHubCategory.tennis);
      expect(organizer.classifySport('Cricket'), SportsHubCategory.other);
    });

    test('partner and regular event labels classify to the same category', () {
      expect(
        organizer.categoryForEvent(game(
          id: '1',
          sport: 'Unknown',
          competition: 'UFC main card',
        )),
        SportsHubCategory.combat,
      );
      expect(
        organizer.categoryForEvent(game(
          id: '2',
          sport: 'American Football',
        )),
        SportsHubCategory.americanFootball,
      );
    });
  });

  group('Sports TV directory', () {
    test('rejects general news and movies from local and partner live TV', () {
      final sports = organizer.mergeSportChannels(
        partnerSports: [channel('Partner sports', group: 'Sports')],
        builtInSports: [channel('Red Bull TV', group: 'Deportes')],
        localChannels: [
          channel('ESPN News', group: 'Sports'),
          channel('Canal 22', group: 'Cultura'),
          channel('ADN 40', group: 'Noticias'),
          channel('FIFA+', group: 'Fútbol'),
          channel('ESPN', group: 'Televisión'),
          channel('DAZN', group: 'Internacional'),
        ],
        partnerGeneral: [
          channel('Partner movie channel', group: 'Movies'),
          channel('TV Cuatro 4.3', group: 'México · Deportes'),
        ],
      );
      expect(sports.map((s) => s.name), containsAll([
        'Partner sports',
        'Red Bull TV',
        'ESPN News',
        'FIFA+',
        'TV Cuatro 4.3',
        'ESPN',
        'DAZN',
      ]));
      expect(sports.map((s) => s.name), isNot(contains('Canal 22')));
      expect(sports.map((s) => s.name), isNot(contains('ADN 40')));
      expect(sports.map((s) => s.name),
          isNot(contains('Partner movie channel')));
      expect(
        organizer.channelsFor(sports, SportsHubCategory.soccer)
            .map((c) => c.name),
        ['FIFA+'],
      );
      expect(
        organizer.generalChannels(sports).map((c) => c.name),
        containsAll(['Partner sports', 'Red Bull TV', 'TV Cuatro 4.3']),
      );
    });

    test('channels from multiple M3U sources join as fallback servers', () {
      final channels = organizer.mergeSportChannels(
        partnerSports: [
          channel('Canal Deportes', group: 'Sports', epgId: 'sport-1',
              streamUrl: 'https://partner.example/master.m3u8'),
        ],
        builtInSports: [
          channel('Canal Deportes', group: 'Deportes', epgId: 'sport-1',
              streamUrl: 'https://backup.example/master.m3u8'),
          channel('Canal Deportes', group: 'Deportes', epgId: 'sport-1',
              streamUrl: 'https://partner.example/master.m3u8'),
        ],
        localChannels: [],
        partnerGeneral: [],
      );
      expect(channels, hasLength(1));
      expect(channels.single.playbackCandidates, hasLength(2));
      expect(channels.single.playbackCandidates.last.uri.host, 'backup.example');
    });

    test('a legitimate sports TV label does not imply a specific sport', () {
      final general = channel('TV Cuatro 4.3', group: 'México Deportes');
      final american = channel('NFL Network', group: 'Deportes');
      expect(organizer.categoryForChannel(general), isNull);
      expect(organizer.categoryForChannel(american),
          SportsHubCategory.americanFootball);
    });
  });

  group('Sport fixtures', () {
    test('filters by selected day and category; dedupes and sorts live first',
        () {
      final fixtures = [
        game(id: 'a', sport: 'Soccer', hour: 18),
        game(id: 'duplicate-id', sport: 'Soccer', hour: 18),
        game(id: 'nfl', sport: 'American Football', hour: 15, live: true),
        game(id: 'ufc', sport: 'Fighting', hour: 20),
        SportsEvent(
          id: 'other-day',
          sport: 'Soccer',
          competition: 'League',
          home: 'Away',
          away: 'B',
          startsAt: DateTime(2026, 10, 12),
        )
      ];
      final day = DateTime(2026, 10, 11);
      expect(
        organizer.eventsFor(fixtures, SportsHubCategory.soccer, day: day),
        hasLength(1),
      );
      expect(
        organizer.eventsFor(fixtures, SportsHubCategory.americanFootball,
            day: day),
        hasLength(1),
      );
      final all = organizer.eventsFor(fixtures, SportsHubCategory.all, day: day);
      expect(all, hasLength(3));
      expect(all.first.sport, 'American Football');
      expect(
        organizer.eventsFor(fixtures, SportsHubCategory.sportsTv, day: day),
        isEmpty,
      );
    });
  });
}
