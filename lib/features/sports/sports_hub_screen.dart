import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/catalog/partner_content_repository.dart';
import '../../data/live_tv/built_in_live_sources.dart';
import '../../data/live_tv/live_tv_repository.dart';
import '../../domain/models/epg_program.dart';
import '../../domain/models/live_channel.dart';
import '../../domain/models/playback_session.dart';
import '../../domain/models/sports_event.dart';
import '../../domain/models/stream_candidate.dart';
import '../../domain/services/sports_channel_language.dart';
import '../../domain/services/sports_hub_organizer.dart';
import 'sports_channel_rail.dart';

String _subtitle(String competition, DateTime startsAt) =>
    '$competition · ${DateFormat.Hm().format(startsAt)}';

IconData _categoryIcon(SportsHubCategory category) => switch (category) {
      SportsHubCategory.all => Icons.apps_rounded,
      SportsHubCategory.soccer => Icons.sports_soccer_rounded,
      SportsHubCategory.americanFootball => Icons.sports_football_rounded,
      SportsHubCategory.basketball => Icons.sports_basketball_rounded,
      SportsHubCategory.baseball => Icons.sports_baseball_rounded,
      SportsHubCategory.combat => Icons.sports_mma_rounded,
      SportsHubCategory.hockey => Icons.sports_hockey_rounded,
      SportsHubCategory.motorsport => Icons.sports_motorsports_rounded,
      SportsHubCategory.tennis => Icons.sports_tennis_rounded,
      SportsHubCategory.other => Icons.sports_rounded,
      SportsHubCategory.sportsTv => Icons.live_tv_rounded,
    };

/// Category-first Sports Hub: same information architecture on phone and TV.
/// Sources can come from POTV addons, M3U, public channels and approved
/// partner catalogs. No partner account/branding/payment UI is used here.
class SportsHubScreen extends ConsumerStatefulWidget {
  const SportsHubScreen({super.key});

  @override
  ConsumerState<SportsHubScreen> createState() => _SportsHubScreenState();
}

class _SportsHubScreenState extends ConsumerState<SportsHubScreen>
    with WidgetsBindingObserver {
  static const organizer = SportsHubOrganizer();
  static const languageService = SportsChannelLanguage();
  SportsLanguagePreference preferredLanguage = SportsLanguagePreference.spanish;
  SportsHubCategory selectedCategory = SportsHubCategory.all;
  DateTime selectedDay = DateUtils.dateOnly(DateTime.now());
  Timer? _catalogTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startRefreshTimer();
    unawaited(_loadPreferredLanguage());
  }

  Future<void> _loadPreferredLanguage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(SportsChannelLanguage.preferenceKey);
      if (!mounted || saved == null) return;
      for (final option in SportsLanguagePreference.values) {
        if (option.name == saved) {
          setState(() => preferredLanguage = option);
          return;
        }
      }
    } catch (_) {
      // A broken preferences store should not prevent channel browsing.
    }
  }

  Future<void> _selectPreferredLanguage(SportsLanguagePreference value) async {
    setState(() => preferredLanguage = value);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(SportsChannelLanguage.preferenceKey, value.name);
    } catch (_) {
      // The in-session choice still works if persistence is unavailable.
    }
  }

  void _startRefreshTimer() {
    _catalogTimer ??= Timer.periodic(
      const Duration(minutes: 2),
      (_) {
        if (mounted) ref.invalidate(partnerContentProvider);
      },
    );
  }

  void _refresh() {
    ref.invalidate(partnerContentProvider);
    ref.invalidate(builtInSportsChannelsProvider);
    ref.invalidate(liveChannelsProvider);
    ref.invalidate(epgProgramsProvider);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(partnerContentProvider);
      _startRefreshTimer();
    } else {
      _catalogTimer?.cancel();
      _catalogTimer = null;
    }
  }

  @override
  void dispose() {
    _catalogTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  List<_SportsNowItem> _buildNowGuide({
    required List<LiveChannel> channels,
    required List<EpgProgram> programs,
    required List<SportsEvent> events,
  }) {
    final now = DateTime.now();
    final result = <_SportsNowItem>[];
    final seen = <String>{};
    final representedChannels = <String>{};

    bool categoryMatchesChannel(LiveChannel channel, EpgProgram program) {
      if (selectedCategory == SportsHubCategory.all ||
          selectedCategory == SportsHubCategory.sportsTv) {
        return true;
      }
      final channelCategory = organizer.categoryForChannel(channel);
      final programCategory = organizer.classifySport(
        '${program.title} ${program.description ?? ''}',
      );
      return channelCategory == selectedCategory ||
          programCategory == selectedCategory;
    }

    for (final channel in channels) {
      final epgId = channel.epgId?.trim().toLowerCase();
      if (epgId == null || epgId.isEmpty) continue;
      EpgProgram? current;
      for (final program in programs) {
        if (program.channelId.trim().toLowerCase() == epgId &&
            program.isOnAir(now)) {
          current = program;
          break;
        }
      }
      if (current == null || !categoryMatchesChannel(channel, current)) {
        continue;
      }
      EpgProgram? next;
      for (final program in programs) {
        if (program.channelId.trim().toLowerCase() != epgId ||
            !program.startsAt.isAfter(now)) {
          continue;
        }
        if (next == null || program.startsAt.isBefore(next.startsAt)) {
          next = program;
        }
      }
      final key = 'epg:$epgId:${current.title.toLowerCase()}';
      if (!seen.add(key)) continue;
      representedChannels.add(channel.id);
      result.add(
        _SportsNowItem(
          title: current.title,
          subtitle: channel.name,
          startsAt: current.startsAt,
          endsAt: current.endsAt,
          candidates: channel.playbackCandidates,
          nextTitle: next?.title,
        ),
      );
    }

    for (final event in events) {
      if (!event.isLive || event.streams.isEmpty) continue;
      if (selectedCategory != SportsHubCategory.all &&
          selectedCategory != SportsHubCategory.sportsTv &&
          organizer.categoryForEvent(event) != selectedCategory) {
        continue;
      }
      final key = 'event:${event.id}';
      if (!seen.add(key)) continue;
      result.add(
        _SportsNowItem(
          title: event.title,
          subtitle: event.competition,
          startsAt: event.startsAt,
          candidates: event.streams,
        ),
      );
    }

    return result.take(18).toList(growable: false);
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final value = await showDatePicker(
      context: context,
      initialDate: selectedDay,
      firstDate: now.subtract(const Duration(days: 30)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (value != null && mounted) {
      setState(() => selectedDay = DateUtils.dateOnly(value));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTv = selectedCategory.isTelevision;
    final partner = ref.watch(partnerContentProvider).asData?.value;
    final builtInState = ref.watch(builtInSportsChannelsProvider);
    final builtIn = builtInState.asData?.value ?? const <LiveChannel>[];
    final local = ref.watch(liveChannelsProvider).asData?.value ??
        const <LiveChannel>[];
    final programs = ref.watch(epgProgramsProvider).asData?.value ??
        const <EpgProgram>[];

    // Local live-TV playlists may contain ordinary news or movies: never
    // display those in Sports Hub merely because they come from an M3U.
    final allChannels = organizer.mergeSportChannels(
      partnerSports: partner?.sportsChannels ?? const <LiveChannel>[],
      builtInSports: builtIn,
      localChannels: local,
      partnerGeneral: partner?.channels ?? const <LiveChannel>[],
    );
    final activeChannels = languageService.preferredChannels(
      organizer.channelsFor(allChannels, selectedCategory), preferredLanguage);
    final generalChannels = languageService.preferredChannels(
      organizer.generalChannels(allChannels), preferredLanguage);

    final guidePrograms = <EpgProgram>[
      ...partner?.guidePrograms ?? const <EpgProgram>[],
      ...programs,
    ];
    final events = organizer
        .eventsFor(
          partner?.sportsEvents ?? const <SportsEvent>[],
          selectedCategory,
          day: selectedDay,
        )
        .where((event) => event.streams.isNotEmpty)
        .toList(growable: false);
    final nowGuide = _buildNowGuide(
      channels: languageService.preferredChannels(
        allChannels,
        preferredLanguage,
      ),
      programs: guidePrograms,
      events: partner?.sportsEvents ?? const <SportsEvent>[],
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sports Hub'),
        actions: [
          IconButton(
            tooltip: 'Actualizar deportes y canales',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 36),
        children: [
          const Text(
            'Tu centro deportivo',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.7,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'Eventos, competiciones y canales organizados por deporte.',
            style: TextStyle(color: Colors.white60),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Icon(Icons.language_rounded, size: 18),
              const SizedBox(width: 7),
              const Expanded(
                child: Text(
                  'Idioma preferido para TV deportiva',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 7,
            children: [
              for (final language in SportsLanguagePreference.values)
                ChoiceChip(
                  key: ValueKey('sports-language-${language.name}'),
                  label: Text(language.label),
                  selected: preferredLanguage == language,
                  onSelected: (_) => unawaited(_selectPreferredLanguage(language)),
                ),
            ],
          ),
          const SizedBox(height: 5),
          const Text(
            'POTV intenta mostrar primero señales en el idioma elegido cuando '
            'esa información está disponible.',
            style: TextStyle(color: Colors.white60, fontSize: 12),
          ),
          const SizedBox(height: 18),
          _SectionHeading(
            label: 'EXPLORAR POR DEPORTE',
            description: 'Elige una categoría o abre TV deportiva.',
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final category in SportsHubCategory.values)
                ChoiceChip(
                  key: ValueKey('sports-category-${category.name}'),
                  avatar: Icon(_categoryIcon(category), size: 18),
                  label: Text(category.title),
                  selected: selectedCategory == category,
                  tooltip: 'Mostrar ${category.title}',
                  onSelected: (_) =>
                      setState(() => selectedCategory = category),
                ),
            ],
          ),
          const SizedBox(height: 20),
          const _SectionHeading(
            label: 'PARRILLA EN VIVO',
            description:
                'Sólo programas y eventos con transmisión confirmada ahora.',
          ),
          const SizedBox(height: 10),
          if (nowGuide.isNotEmpty)
            _SportsNowRail(items: nowGuide)
          else
            const _EmptySection(
              'No hay una transmisión deportiva en vivo confirmada ahora. '
              'Consulta TV deportiva para ver las señales disponibles.',
            ),
          const SizedBox(height: 22),
          if (isTv) ...[
            _SectionHeading(
              label: 'TV DEPORTIVA',
              description: '${languageService.preferredChannels(allChannels, preferredLanguage).length} canales según tu idioma preferido.',
            ),
            if (builtInState.isLoading && allChannels.isEmpty)
              const LinearProgressIndicator(minHeight: 2),
            if (allChannels.isEmpty && !builtInState.isLoading)
              const _EmptySection(
                'No encontramos señales deportivas disponibles en este momento.',
              ),
            for (final sport in SportsHubCategory.values)
              if (sport != SportsHubCategory.all &&
                  sport != SportsHubCategory.sportsTv &&
                  sport != SportsHubCategory.other &&
                  languageService.preferredChannels(
                    organizer.channelsFor(allChannels, sport),
                    preferredLanguage,
                  ).isNotEmpty) ...[
                const SizedBox(height: 19),
                _SectionHeading(
                  label: 'CANALES · ${sport.title.toUpperCase()}',
                  description: 'Señales dedicadas a ${sport.title.toLowerCase()}.',
                ),
                const SizedBox(height: 9),
                SportsChannelRail(
                  channels: languageService.preferredChannels(
                    organizer.channelsFor(allChannels, sport),
                    preferredLanguage,
                  ),
                  preferredLanguage: preferredLanguage,
                ),
              ],
            if (generalChannels.isNotEmpty) ...[
              const SizedBox(height: 20),
              const _SectionHeading(
                label: 'TV DEPORTIVA GENERAL',
                description: 'Canales que transmiten distintas disciplinas.',
              ),
              const SizedBox(height: 9),
              SportsChannelRail(
                channels: generalChannels,
                preferredLanguage: preferredLanguage,
              ),
            ],
          ] else ...[
            _SectionHeading(
              label: selectedCategory == SportsHubCategory.all
                  ? 'AGENDA DEPORTIVA'
                  : 'AGENDA · ${selectedCategory.title.toUpperCase()}',
              description: DateFormat('EEE d MMM').format(selectedDay),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Hoy'),
                  selected: DateUtils.isSameDay(
                    selectedDay,
                    DateTime.now(),
                  ),
                  onSelected: (_) => setState(() {
                    selectedDay = DateUtils.dateOnly(DateTime.now());
                  }),
                ),
                ChoiceChip(
                  label: const Text('Mañana'),
                  selected: DateUtils.isSameDay(
                    selectedDay,
                    DateTime.now().add(const Duration(days: 1)),
                  ),
                  onSelected: (_) => setState(() {
                    selectedDay = DateUtils.dateOnly(
                      DateTime.now().add(const Duration(days: 1)),
                    );
                  }),
                ),
                OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_month_rounded),
                  label: const Text('Elegir fecha'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (activeChannels.isNotEmpty) ...[
              _SectionHeading(
                label: selectedCategory == SportsHubCategory.all
                    ? 'CANALES DEPORTIVOS'
                    : 'CANALES · ${selectedCategory.title.toUpperCase()}',
                description: 'Señales para esta categoría.',
              ),
              const SizedBox(height: 9),
              SportsChannelRail(
                channels: activeChannels,
                preferredLanguage: preferredLanguage,
              ),
              const SizedBox(height: 20),
            ],
            if (selectedCategory != SportsHubCategory.all &&
                generalChannels.isNotEmpty) ...[
              const _SectionHeading(
                label: 'TV DEPORTIVA GENERAL',
                description: 'Más señales deportivas disponibles.',
              ),
              const SizedBox(height: 9),
              SportsChannelRail(
                channels: generalChannels,
                preferredLanguage: preferredLanguage,
              ),
              const SizedBox(height: 22),
            ],
            if (events.isNotEmpty) ...[
              _SectionHeading(
                label: 'PARTIDOS Y EVENTOS',
                description: '${events.length} con transmisión confirmada.',
              ),
              const SizedBox(height: 10),
              for (final event in events)
                _SportsEventCard(event: event),
            ] else if (activeChannels.isEmpty && generalChannels.isEmpty)
              _EmptySection(
                'No hay eventos ni señales de ${selectedCategory.title.toLowerCase()} '
                'para esta fecha. Prueba otro deporte o consulta TV deportiva.',
              ),
          ],
        ],
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  final String label;
  final String description;

  const _SectionHeading({
    required this.label,
    required this.description,
  });

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 3),
          Text(description,
              style: const TextStyle(color: Colors.white60, fontSize: 13)),
        ],
      );
}

class _EmptySection extends StatelessWidget {
  final String message;
  const _EmptySection(this.message);

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Row(
            children: [
              const Icon(Icons.sports_outlined, size: 28),
              const SizedBox(width: 12),
              Expanded(child: Text(message)),
            ],
          ),
        ),
      );
}

class _SportsNowItem {
  final String title;
  final String subtitle;
  final DateTime startsAt;
  final DateTime? endsAt;
  final List<StreamCandidate> candidates;
  final String? nextTitle;

  const _SportsNowItem({
    required this.title,
    required this.subtitle,
    required this.startsAt,
    this.endsAt,
    required this.candidates,
    this.nextTitle,
  });
}

class _SportsNowRail extends StatelessWidget {
  final List<_SportsNowItem> items;

  const _SportsNowRail({required this.items});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return SizedBox(
      height: 178,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final item = items[index];
          final duration = item.endsAt?.difference(item.startsAt);
          final elapsed = now.difference(item.startsAt);
          final progress = duration == null ||
                  duration.inMilliseconds <= 0 ||
                  elapsed.isNegative
              ? null
              : (elapsed.inMilliseconds / duration.inMilliseconds)
                  .clamp(0.0, 1.0)
                  .toDouble();
          return SizedBox(
            width: 260,
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: item.candidates.isEmpty
                    ? null
                    : () => context.push(
                          '/player',
                          extra: PlaybackSession(
                            title: item.title,
                            candidates: item.candidates,
                            isLive: true,
                          ),
                        ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.circle,
                            size: 9,
                            color: Colors.redAccent,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'EN VIVO',
                            style: TextStyle(
                              color: Colors.redAccent,
                              fontWeight: FontWeight.w900,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        item.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 12,
                        ),
                      ),
                      if (item.nextTitle != null) ...[
                        const SizedBox(height: 5),
                        Text(
                          'Después · ${item.nextTitle}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                          ),
                        ),
                      ],
                      const Spacer(),
                      if (progress != null)
                        LinearProgressIndicator(
                          value: progress,
                          minHeight: 3,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SportsEventCard extends StatelessWidget {
  final SportsEvent event;

  const _SportsEventCard({required this.event});

  @override
  Widget build(BuildContext context) {
    final playable = event.streams;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 10,
        ),
        leading: Icon(_sportIcon(event.sport)),
        title: Text(
          event.title,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_subtitle(event.competition, event.startsAt)),
            if (event.isLive)
              const Text(
                'EN VIVO',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Colors.redAccent,
                ),
              ),
            const Text(
              'Transmisión del evento disponible',
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
        trailing: FilledButton(
          onPressed: () => context.push(
            '/player',
            extra: PlaybackSession(
              title: event.title,
              candidates: playable,
              isLive: true,
            ),
          ),
          child: const Text('VER EVENTO'),
        ),
      ),
    );
  }

  IconData _sportIcon(String sport) {
    final value = sport.toLowerCase();
    if (value.contains('soccer')) return Icons.sports_soccer;
    if (value.contains('basket')) return Icons.sports_basketball;
    if (value.contains('american')) return Icons.sports_football;
    if (value.contains('baseball')) return Icons.sports_baseball;
    if (value.contains('hockey')) return Icons.sports_hockey;
    if (value.contains('motor')) return Icons.sports_motorsports;
    if (value.contains('tennis')) return Icons.sports_tennis;
    if (value.contains('fight') || value.contains('boxing')) {
      return Icons.sports_mma;
    }
    return Icons.sports;
  }
}
