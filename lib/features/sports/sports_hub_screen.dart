import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/catalog/partner_content_repository.dart';
import '../../data/live_tv/built_in_live_sources.dart';
import '../../data/live_tv/live_tv_repository.dart';
import '../../data/sports/addon_sports_repository.dart';
import '../../data/sports/sports_repository.dart';
import '../../domain/models/addon_sports_item.dart';
import '../../domain/models/epg_program.dart';
import '../../domain/models/live_channel.dart';
import '../../domain/models/playback_session.dart';
import '../../domain/models/sports_event.dart';
import '../../domain/models/stream_candidate.dart';
import '../../domain/services/sports_channel_resolver.dart';
import '../../domain/services/sports_channel_language.dart';
import '../../domain/services/sports_hub_organizer.dart';
import 'addon_sports_rail.dart';
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
  SportsHubCategory selectedCategory = SportsHubCategory.soccer;
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
    if (!selectedCategory.isTelevision) {
      ref.invalidate(sportsEventsProvider(
        (day: selectedDay, sport: selectedCategory.apiSport),
      ));
      ref.invalidate(addonSportsItemsProvider(
        selectedCategory.apiSport ?? 'all',
      ));
    }
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

    // Outside the TV-directory view, keep the rail useful even when a channel
    // has no compatible EPG id. In TV deportiva the channel rail below already
    // shows those raw signals, so repeating them here would duplicate cards and
    // would turn "EN VIVO AHORA" into a second channel directory.
    if (selectedCategory == SportsHubCategory.sportsTv) {
      return result.take(18).toList(growable: false);
    }
    for (final channel in channels) {
      if (result.length >= 18 || representedChannels.contains(channel.id)) {
        continue;
      }
      if (selectedCategory != SportsHubCategory.all &&
          selectedCategory != SportsHubCategory.sportsTv &&
          organizer.categoryForChannel(channel) != selectedCategory) {
        continue;
      }
      final key = 'channel:${channel.id}';
      if (!seen.add(key)) continue;
      representedChannels.add(channel.id);
      result.add(
        _SportsNowItem(
          title: channel.name,
          subtitle: 'Señal deportiva disponible',
          startsAt: now,
          candidates: channel.playbackCandidates,
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
    final query = (day: selectedDay, sport: selectedCategory.apiSport);
    final eventsState = isTv
        ? const AsyncData<List<SportsEvent>>([])
        : ref.watch(sportsEventsProvider(query));
    final addonsState = isTv
        ? const AsyncData<List<AddonSportsItem>>([])
        : ref.watch(
            addonSportsItemsProvider(selectedCategory.apiSport ?? 'all'),
          );
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

    final events = organizer.eventsFor(
      [
        ...partner?.sportsEvents ?? const <SportsEvent>[],
        ...eventsState.asData?.value ?? const <SportsEvent>[],
      ],
      selectedCategory,
      day: selectedDay,
    );
    final addonItems = addonsState.asData?.value ??
        const <AddonSportsItem>[];
    final nowGuide = _buildNowGuide(
      channels: languageService.preferredChannels(
        allChannels,
        preferredLanguage,
      ),
      programs: programs,
      events: [
        ...partner?.sportsEvents ?? const <SportsEvent>[],
        ...eventsState.asData?.value ?? const <SportsEvent>[],
      ],
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
          if (nowGuide.isNotEmpty) ...[
            const _SectionHeading(
              label: 'EN VIVO AHORA',
              description:
                  'Programas al aire y señales deportivas disponibles ahora.',
            ),
            const SizedBox(height: 10),
            _SportsNowRail(items: nowGuide),
            const SizedBox(height: 22),
          ],
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
            if (addonsState.isLoading)
              const LinearProgressIndicator(minHeight: 2),
            if (addonItems.isNotEmpty) ...[
              _SectionHeading(
                label: 'MÁS EVENTOS',
                description: '${addonItems.length} eventos disponibles.',
              ),
              const SizedBox(height: 10),
              AddonSportsRail(items: addonItems),
              const SizedBox(height: 20),
            ],
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
            if (eventsState.isLoading && events.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 22),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (eventsState.hasError && events.isEmpty)
              const _EmptySection(
                'No pudimos actualizar la agenda. Las señales disponibles '
                'siguen funcionando.',
              ),
            if (events.isNotEmpty) ...[
              _SectionHeading(
                label: 'PARTIDOS Y EVENTOS',
                description: '${events.length} programados o en vivo.',
              ),
              const SizedBox(height: 10),
              for (final event in events)
                _SportsEventCard(
                  event: event,
                  channels: languageService.preferredChannels(
                    allChannels,
                    preferredLanguage,
                  ),
                  programs: programs,
                ),
            ] else if (!eventsState.isLoading && !eventsState.hasError &&
                addonItems.isEmpty && activeChannels.isEmpty &&
                generalChannels.isEmpty)
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

  const _SportsNowItem({
    required this.title,
    required this.subtitle,
    required this.startsAt,
    this.endsAt,
    required this.candidates,
  });
}

class _SportsNowRail extends StatelessWidget {
  final List<_SportsNowItem> items;

  const _SportsNowRail({required this.items});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return SizedBox(
      height: 154,
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
  final List<LiveChannel> channels;
  final List<EpgProgram> programs;

  const _SportsEventCard({
    required this.event,
    required this.channels,
    required this.programs,
  });

  @override
  Widget build(BuildContext context) {
    const resolver = SportsChannelResolver();
    final matches = resolver.resolve(
      event: event,
      channels: channels,
      programs: programs,
    );
    final best = matches.isEmpty ? null : matches.first;
    // Direct watch candidates are returned by the authorized partner for
    // this exact event. EPG matches are a lower-priority verified fallback.
    final eventStreams = event.streams;
    final playable = eventStreams.isNotEmpty
        ? eventStreams
        : [for (final match in matches) ...match.channel.playbackCandidates];
    final hasConfirmedBroadcast = playable.isNotEmpty;

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
            if (eventStreams.isNotEmpty)
              const Text(
                'Transmisión del evento disponible',
                style: TextStyle(color: Colors.white70),
              )
            else if (best != null)
              Text(
                best.program?.title ?? 'Disponible en ${best.channel.name}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70),
              ),
          ],
        ),
        trailing: hasConfirmedBroadcast
            ? FilledButton(
                onPressed: () => context.push(
                  '/player',
                  extra: PlaybackSession(
                    title: event.title,
                    candidates: playable,
                    isLive: true,
                  ),
                ),
                child: const Text('VER EVENTO'),
              )
            : Text(
                DateFormat.Hm().format(event.startsAt),
                style: const TextStyle(
                  color: Colors.white54,
                  fontWeight: FontWeight.w700,
                ),
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
