import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:potv/data/catalog/partner_content_repository.dart';
import 'package:potv/data/live_tv/built_in_live_sources.dart';
import 'package:potv/data/live_tv/live_tv_repository.dart';
import 'package:potv/data/sports/addon_sports_repository.dart';
import 'package:potv/data/sports/sports_repository.dart';
import 'package:potv/domain/models/epg_program.dart';
import 'package:potv/domain/models/live_channel.dart';
import 'package:potv/domain/models/partner_content_snapshot.dart';
import 'package:potv/domain/models/sports_event.dart';
import 'package:potv/domain/models/stream_candidate.dart';
import 'package:potv/features/sports/sports_hub_screen.dart';

class _TestLiveChannelsController extends LiveChannelsController {
  @override
  Future<List<LiveChannel>> build() async => [];
}

class _TestEpgController extends EpgProgramsController {
  @override
  Future<List<EpgProgram>> build() async => [];
}

void main() {
  testWidgets('sports categories select NFL separately from soccer', (
    tester,
  ) async {
    // Large TV-like viewport lets the fixture cards render within the
    // lazily built vertical list, independently of host test window size.
    tester.view.physicalSize = const Size(1280, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final day = DateUtils.dateOnly(DateTime.now());
    final events = <SportsEvent>[
      SportsEvent(
        id: 'soccer',
        sport: 'Soccer',
        competition: 'Liga MX',
        home: 'América',
        away: 'Pumas',
        startsAt: DateTime(day.year, day.month, day.day, 15),
      ),
      SportsEvent(
        id: 'nfl',
        sport: 'American Football',
        competition: 'NFL',
        home: 'Chiefs',
        away: 'Bills',
        startsAt: DateTime(day.year, day.month, day.day, 18),
      ),
    ];
    final sportsChannel = LiveChannel(
      id: 'sports-news',
      name: 'POTV Deportes',
      group: 'TV Deportiva',
      stream: StreamCandidate(
        id: 'sports-news',
        label: 'TV Deportiva',
        uri: Uri.parse('https://example.org/sports.m3u8'),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          partnerContentProvider.overrideWith(
            (ref) async => PartnerContentSnapshot(
              revision: 'rev-1',
              fetchedAt: DateTime.now(),
              sportsEvents: events,
              sportsChannels: [sportsChannel],
            ),
          ),
          builtInSportsChannelsProvider.overrideWith(
            (ref) async => <LiveChannel>[],
          ),
          liveChannelsProvider.overrideWith(_TestLiveChannelsController.new),
          epgProgramsProvider.overrideWith(_TestEpgController.new),
          sportsEventsProvider.overrideWith(
            (ref, query) async => <SportsEvent>[],
          ),
          addonSportsItemsProvider.overrideWith(
            (ref, sport) async => [],
          ),
        ],
        child: const MaterialApp(home: SportsHubScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('América vs Pumas'), findsOneWidget);
    expect(find.text('Chiefs vs Bills'), findsNothing);

    await tester.tap(find.byKey(
      const ValueKey('sports-category-americanFootball'),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Chiefs vs Bills'), findsOneWidget);
    expect(find.text('América vs Pumas'), findsNothing);

    await tester.ensureVisible(
      find.byKey(const ValueKey('sports-category-sportsTv')),
    );
    await tester.tap(find.byKey(
      const ValueKey('sports-category-sportsTv'),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('TV DEPORTIVA'), findsOneWidget);
    expect(find.text('POTV Deportes'), findsOneWidget);
    expect(find.text('Chiefs vs Bills'), findsNothing);
  });
}
