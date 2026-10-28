import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:potv/data/catalog/partner_content_repository.dart';
import 'package:potv/data/live_tv/built_in_live_sources.dart';
import 'package:potv/data/live_tv/live_tv_repository.dart';
import 'package:potv/domain/models/epg_program.dart';
import 'package:potv/domain/models/live_channel.dart';
import 'package:potv/domain/models/partner_content_snapshot.dart';
import 'package:potv/domain/models/stream_candidate.dart';
import 'package:potv/features/live_tv/live_tv_screen.dart';

class _Channels extends LiveChannelsController {
  @override
  Future<List<LiveChannel>> build() async => [
    LiveChannel(
      id: 'news-local',
      name: 'Noticias Uno',
      group: 'México · Noticias',
      epgId: 'news-1',
      stream: StreamCandidate(
        id: 'local-news',
        label: 'Noticias Uno',
        uri: Uri.parse('https://example.org/news.m3u8'),
      ),
    ),
    LiveChannel(
      id: 'sport-local',
      name: 'Deportes MX Local',
      group: 'México · Deportes',
      stream: StreamCandidate(
        id: 'local-sport',
        label: 'Deportes MX Local',
        uri: Uri.parse('https://example.org/sports-local.m3u8'),
      ),
    ),
    LiveChannel(
      id: 'film-local',
      name: 'Canal Cine',
      group: 'Películas',
      stream: StreamCandidate(
        id: 'local-film',
        label: 'Canal Cine',
        uri: Uri.parse('https://example.org/cinema.m3u8'),
      ),
    ),
  ];
}

class _PendingChannels extends LiveChannelsController {
  @override
  Future<List<LiveChannel>> build() => Completer<List<LiveChannel>>().future;
}

class _Guide extends EpgProgramsController {
  @override
  Future<List<EpgProgram>> build() async => const [];
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('starter TV channels render before slow playlists finish', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          partnerContentProvider.overrideWith(
            (ref) => Completer<PartnerContentSnapshot>().future,
          ),
          liveChannelsProvider.overrideWith(_PendingChannels.new),
          epgProgramsProvider.overrideWith(_Guide.new),
        ],
        child: const MaterialApp(home: LiveTvScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('ADN 40'), findsOneWidget);
    expect(find.textContaining('1 canal'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('TV grid keeps local M3U sports and excludes sports-only feed', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final now = DateTime.now();
    final snapshot = PartnerContentSnapshot(
      revision: 'v1',
      fetchedAt: now,
      sportsChannels: [
        LiveChannel(
          id: 'partner:sport:1',
          name: 'POTV Sports Uno',
          group: 'Deportes',
          stream: StreamCandidate(
            id: 'partner-sport',
            label: 'Deportes',
            uri: Uri.parse('https://cdn.example/sports.m3u8'),
          ),
        ),
      ],
      guidePrograms: [
        EpgProgram(
          channelId: 'news-1',
          title: 'Resumen de hoy',
          startsAt: now.subtract(const Duration(minutes: 15)),
          endsAt: now.add(const Duration(minutes: 15)),
        ),
        EpgProgram(
          channelId: 'news-1',
          title: 'Noticias mañana',
          startsAt: now.add(const Duration(minutes: 15)),
          endsAt: now.add(const Duration(minutes: 45)),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          partnerContentProvider.overrideWith((ref) async => snapshot),
          builtInSportsChannelsProvider.overrideWith((ref) async => []),
          liveChannelsProvider.overrideWith(_Channels.new),
          epgProgramsProvider.overrideWith(_Guide.new),
        ],
        child: const MaterialApp(home: LiveTvScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Noticias Uno'), findsOneWidget);
    expect(find.text('POTV Sports Uno'), findsNothing);
    expect(find.text('Deportes MX Local'), findsOneWidget);
    expect(find.text('Canal Cine'), findsOneWidget);
    expect(find.text('AHORA · Resumen de hoy'), findsOneWidget);
    expect(find.textContaining('Después · Noticias mañana'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('live-tv-category-sports')));
    await tester.pump();
    expect(find.text('POTV Sports Uno'), findsNothing);
    expect(find.text('Deportes MX Local'), findsOneWidget);
    expect(find.text('Noticias Uno'), findsNothing);
    expect(find.text('Canal Cine'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('live-tv-category-all')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('live-tv-search')),
      'Noticias mañana',
    );
    await tester.pump();
    expect(find.text('Noticias Uno'), findsOneWidget);
    expect(find.text('Canal Cine'), findsNothing);
  });

  testWidgets('favorite toggle and filter keep the selected local channel', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 960);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          partnerContentProvider.overrideWith(
            (ref) async => PartnerContentSnapshot.empty(),
          ),
          builtInSportsChannelsProvider.overrideWith((ref) async => []),
          liveChannelsProvider.overrideWith(_Channels.new),
          epgProgramsProvider.overrideWith(_Guide.new),
        ],
        child: const MaterialApp(home: LiveTvScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byKey(const ValueKey('live-tv-star-news-local')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('live-tv-favorites')));
    await tester.pump();

    expect(find.text('Noticias Uno'), findsOneWidget);
    expect(find.text('Canal Cine'), findsNothing);
  });


  testWidgets('Parrilla shows verified programs and keeps unlisted TV visible', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1360, 1040);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final now = DateTime.now();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          partnerContentProvider.overrideWith(
            (ref) async => PartnerContentSnapshot(
              revision: 'guide-one',
              fetchedAt: now,
              guidePrograms: [
                EpgProgram(
                  channelId: 'news-1',
                  title: 'Noticias verificadas',
                  startsAt: now.subtract(const Duration(minutes: 8)),
                  endsAt: now.add(const Duration(minutes: 22)),
                ),
                EpgProgram(
                  channelId: 'news-1',
                  title: 'Después en noticias',
                  startsAt: now.add(const Duration(minutes: 22)),
                  endsAt: now.add(const Duration(minutes: 52)),
                ),
              ],
            ),
          ),
          builtInSportsChannelsProvider.overrideWith((ref) async => []),
          liveChannelsProvider.overrideWith(_Channels.new),
          epgProgramsProvider.overrideWith(_Guide.new),
        ],
        child: const MaterialApp(home: LiveTvScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('Parrilla'));
    await tester.pump();

    expect(find.byKey(const ValueKey('live-tv-guide-list')), findsOneWidget);
    expect(find.textContaining('Noticias verificadas'), findsWidgets);
    expect(find.text('Noticias Uno'), findsOneWidget);
    expect(find.text('Canal Cine'), findsOneWidget);
    expect(find.text('Sin datos de programación'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('live-tv-with-schedule')));
    await tester.pump();
    expect(find.text('Noticias Uno'), findsOneWidget);
    expect(find.text('Canal Cine'), findsNothing);
    expect(find.textContaining('Después en noticias'), findsOneWidget);

    await tester.tap(find.text('Canales'));
    await tester.pump();
    expect(find.byKey(const ValueKey('live-tv-channel-grid')), findsOneWidget);
    expect(find.text('Canal Cine'), findsOneWidget);
  });
\n}\n