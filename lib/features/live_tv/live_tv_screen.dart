import 'dart:async';
import 'package:flutter/material.dart';
import 'package:potv/ui/branding/potv_animated_assets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/catalog/partner_content_repository.dart';
import '../../data/live_tv/built_in_live_sources.dart';
import '../../domain/services/live_tv_organizer.dart';
import '../../data/live_tv/live_tv_favorites.dart';
import '../../data/live_tv/live_tv_repository.dart';
import '../../data/sources/stream_candidate_probe.dart';
import '../../domain/models/epg_program.dart';
import '../../domain/models/live_channel.dart';
import '../../domain/models/playback_session.dart';
import 'live_tv_program_guide.dart';

enum _TvDisplayMode { cards, guide }

class LiveTvScreen extends ConsumerStatefulWidget {
  const LiveTvScreen({super.key});

  @override
  ConsumerState<LiveTvScreen> createState() => _LiveTvScreenState();
}

class _LiveTvScreenState extends ConsumerState<LiveTvScreen>
    with WidgetsBindingObserver {
  Timer? _partnerRefreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startTimers();
  }

  void _startTimers() {
    _partnerRefreshTimer ??= Timer.periodic(const Duration(minutes: 2), (_) {
      if (mounted) ref.invalidate(partnerContentProvider);
    });
    _guideClock ??= Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() => _guideNow = DateTime.now());
    });
  }

  @override
  void dispose() {
    _guideClock?.cancel();
    _partnerRefreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(partnerContentProvider);
      setState(() => _guideNow = DateTime.now());
      _startTimers();
    } else {
      _partnerRefreshTimer?.cancel();
      _partnerRefreshTimer = null;
      _guideClock?.cancel();
      _guideClock = null;
    }
  }

  String searchQuery = '';
  LiveTvCategory selectedCategory = LiveTvCategory.all;
  bool favoritesOnly = false;
  bool guideOnly = false;
  _TvDisplayMode displayMode = _TvDisplayMode.cards;
  Timer? _guideClock;
  DateTime _guideNow = DateTime.now();
  String? _openingChannelId;

  static const _organizer = LiveTvOrganizer();

  void _refreshAll() {
    ref.read(liveChannelsProvider.notifier).refresh();
    ref.invalidate(partnerContentProvider);
    ref.invalidate(builtInSportsChannelsProvider);
    ref.read(epgProgramsProvider.notifier).refresh();
  }

  Future<void> _playChannel(LiveChannel selected) async {
    if (_openingChannelId != null) return;
    setState(() => _openingChannelId = selected.id);
    try {
      var channel = selected;
      if (selected.id.startsWith('partner:')) {
        // Signed partner URLs may expire while the user browses the grid.
        // Resolve the latest catalog immediately before opening a channel.
        final snapshot = await ref
            .read(partnerContentRepositoryProvider)
            .load();
        if (!mounted) return;
        final matches = [
          ...snapshot.channels,
          ...snapshot.sportsChannels,
        ].where((item) => item.id == selected.id);
        if (matches.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Este canal ya no está disponible en el catálogo.'),
            ),
          );
          ref.invalidate(partnerContentProvider);
          return;
        }
        channel = matches.first;
        ref.invalidate(partnerContentProvider);
      }

      // The signed gateway stream is an open-ended transport stream.
      // A HEAD probe cannot certify playback and may hang unnecessarily.
      // Open the player promptly; let Media3 report decoder/network errors.
      final playable = channel.id.startsWith('partner:')
          ? channel.playbackCandidates
          : await ref
                .read(streamCandidateProbeProvider)
                .preferReachable(
                  channel.playbackCandidates,
                  dropDeadWhenCertain: true,
                );
      if (!mounted) return;

      if (playable.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Esta señal no está respondiendo. Prueba otra opción.',
            ),
          ),
        );
        return;
      }

      context.push(
        '/player',
        extra: PlaybackSession(
          title: channel.name,
          candidates: playable,
          isLive: true,
        ),
      );
    } finally {
      if (mounted) setState(() => _openingChannelId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final channelsState = ref.watch(liveChannelsProvider);
    final starterChannels = ref.watch(starterMexicoChannelsProvider);
    final partnerState = ref.watch(partnerContentProvider);
    final epgState = ref.watch(epgProgramsProvider);
    final favoritesState = ref.watch(liveTvFavoritesProvider);
    final partner = partnerState.asData?.value;
    final favorites = favoritesState.asData?.value ?? const <String>{};
    final programs = [
      ...partner?.guidePrograms ?? const <EpgProgram>[],
      ...epgState.asData?.value ?? const <EpgProgram>[],
    ];
    final guide = LiveTvGuide(programs);
    final channels = _organizer.merge(
      partner: partner?.channels ?? const <LiveChannel>[],
      local: [
        ...starterChannels,
        ...channelsState.asData?.value ?? const <LiveChannel>[],
      ],
      // Dedicated sports feeds belong in Sports Hub. Ordinary Mexico TV
      // channels that happen to be sports remain available through local or
      // partner general TV catalogs.
      partnerSports: const <LiveChannel>[],
      publicSports: const <LiveChannel>[],
    );
    final counts = _organizer.counts(channels);
    final filtered = _organizer.filter(
      channels,
      category: selectedCategory,
      search: searchQuery,
      favorites: favorites,
      favoritesOnly: favoritesOnly,
      guide: guide,
      now: _guideNow,
    );
    final onlyFavorites = [
      ...filtered.where((c) => _isFavorite(c, favorites)),
      ...filtered.where((c) => !_isFavorite(c, favorites)),
    ];
    final guideCoverage = onlyFavorites.where((channel) =>
        guide.onAir(channel, _guideNow) != null ||
        guide.upNext(channel, _guideNow) != null).length;
    final displayed = displayMode == _TvDisplayMode.guide && guideOnly
        ? onlyFavorites.where((channel) =>
            guide.onAir(channel, _guideNow) != null ||
            guide.upNext(channel, _guideNow) != null).toList()
        : onlyFavorites;
    final loading = channelsState.isLoading || partnerState.isLoading;
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 600;

    return Scaffold(
      appBar: AppBar(
        title: const Text('TV en vivo'),
        actions: [
          IconButton(
            tooltip: 'Actualizar canales y programación',
            onPressed: _refreshAll,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 16 : 24,
              12,
              compact ? 16 : 24,
              8,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Explora tus canales',
                        style: TextStyle(
                          fontSize: compact ? 22 : 28,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Text(
                      '${channels.length} canales',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  key: const ValueKey('live-tv-search'),
                  onChanged: (value) => setState(() => searchQuery = value),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded),
                    hintText: 'Canal, categoría o programa',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 52,
            child: ListView(
              padding: EdgeInsets.symmetric(horizontal: compact ? 16 : 24),
              scrollDirection: Axis.horizontal,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 9),
                  child: FilterChip(
                    key: const ValueKey('live-tv-favorites'),
                    label: const Text('Favoritos'),
                    avatar: const Icon(Icons.star_rounded, size: 17),
                    selected: favoritesOnly,
                    onSelected: (value) =>
                        setState(() => favoritesOnly = value),
                  ),
                ),
                for (final category in LiveTvCategory.values)
                  if (category == LiveTvCategory.all ||
                      (counts[category] ?? 0) > 0 ||
                      selectedCategory == category)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        key: ValueKey('live-tv-category-${category.name}'),
                        label: Text(
                          '${category.label} ${counts[category] ?? 0}',
                        ),
                        selected: selectedCategory == category,
                        onSelected: (_) =>
                            setState(() => selectedCategory = category),
                      ),
                    ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(compact ? 16 : 24, 3,
                compact ? 16 : 24, 8),
            child: SegmentedButton<_TvDisplayMode>(
              key: const ValueKey('live-tv-display-mode'),
              segments: const [
                ButtonSegment(
                  value: _TvDisplayMode.cards,
                  label: Text('Canales'),
                  icon: Icon(Icons.grid_view_rounded, size: 18),
                ),
                ButtonSegment(
                  value: _TvDisplayMode.guide,
                  label: Text('Parrilla'),
                  icon: Icon(Icons.view_list_rounded, size: 18),
                ),
              ],
              selected: {displayMode},
              onSelectionChanged: (selection) =>
                  setState(() => displayMode = selection.first),
            ),
          ),
          if (displayMode == _TvDisplayMode.guide)
            Padding(
              padding: EdgeInsets.fromLTRB(
                  compact ? 16 : 24, 0, compact ? 16 : 24, 8),
              child: Row(
                children: [
                  FilterChip(
                    key: const ValueKey('live-tv-with-schedule'),
                    label: const Text('Con programación'),
                    avatar: const Icon(Icons.schedule_rounded, size: 18),
                    selected: guideOnly,
                    onSelected: (value) =>
                        setState(() => guideOnly = value),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '$guideCoverage de ' + onlyFavorites.length.toString() +
                          ' canales con guía',
                      textAlign: TextAlign.end,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, color: Colors.white60),
                    ),
                  ),
                ],
              ),
            ),
          if (loading && channels.isNotEmpty) const PotvLoadingFlag(width: 72),

          if (channels.isNotEmpty && channelsState.hasError)
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 6, 20, 2),
              child: Text(
                'Una fuente no respondió; mostramos los canales disponibles.',
                style: TextStyle(color: Colors.orangeAccent, fontSize: 12),
              ),
            ),
          Expanded(
            child: channels.isEmpty && loading
                ? const Center(child: PotvLoadingFlag(width: 44))
                : channels.isEmpty
                ? const _EmptyTv()
                : displayed.isEmpty
                ? Center(child: Text(
                    guideOnly && displayMode == _TvDisplayMode.guide
                    ? 'No hay programación disponible para este filtro.'
                    : 'No hay canales con ese filtro.'))
                : displayMode == _TvDisplayMode.guide
                ? ListView.builder(
                    key: const ValueKey('live-tv-guide-list'),
                    padding: EdgeInsets.fromLTRB(
                        compact ? 12 : 20, 4, compact ? 12 : 20, 24),
                    itemCount: displayed.length,
                    itemBuilder: (context, index) {
                      final channel = displayed[index];
                      return LiveTvProgramGuideRow(
                        channel: channel,
                        category: _organizer.categoryFor(channel),
                        current: guide.onAir(channel, _guideNow),
                        next: guide.upNext(channel, _guideNow),
                        now: _guideNow,
                        compact: compact,
                        favorite: _isFavorite(channel, favorites),
                        opening: _openingChannelId == channel.id,
                        onOpen: () => _playChannel(channel),
                        onFavorite: () => ref
                            .read(liveTvFavoritesProvider.notifier)
                            .toggle(channel),
                      );
                    },
                  )
                : GridView.builder(
                    key: const ValueKey('live-tv-channel-grid'),
                    padding: EdgeInsets.fromLTRB(
                      compact ? 12 : 20,
                      12,
                      compact ? 12 : 20,
                      24,
                    ),
                    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: compact ? 360 : 340,
                      mainAxisExtent: 192,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: displayed.length,
                    itemBuilder: (context, index) {
                      final channel = displayed[index];
                      return _LiveChannelCard(
                        channel: channel,
                        category: _organizer.categoryFor(channel),
                        current: guide.onAir(channel, _guideNow),
                        next: guide.upNext(channel, _guideNow),
                        now: _guideNow,
                        favorite: _isFavorite(channel, favorites),
                        opening: _openingChannelId == channel.id,
                        onOpen: () => _playChannel(channel),
                        onFavorite: () => ref
                            .read(liveTvFavoritesProvider.notifier)
                            .toggle(channel),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  bool _isFavorite(LiveChannel channel, Set<String> favorites) {
    final epg = channel.epgId?.trim();
    return (epg != null && epg.isNotEmpty && favorites.contains('epg:$epg')) ||
        favorites.contains('name:${channel.name.trim().toLowerCase()}');
  }
}

class _LiveChannelCard extends StatelessWidget {
  final LiveChannel channel;
  final LiveTvCategory category;
  final EpgProgram? current;
  final EpgProgram? next;
  final DateTime now;
  final bool favorite;
  final bool opening;
  final VoidCallback onOpen;
  final VoidCallback onFavorite;

  const _LiveChannelCard({
    required this.channel,
    required this.category,
    required this.current,
    required this.next,
    required this.now,
    required this.favorite,
    required this.opening,
    required this.onOpen,
    required this.onFavorite,
  });

  @override
  Widget build(BuildContext context) {
    final progress =
        current == null || !current!.endsAt.isAfter(current!.startsAt)
        ? null
        : (now.difference(current!.startsAt).inMilliseconds /
                  current!.endsAt.difference(current!.startsAt).inMilliseconds)
              .clamp(0.0, 1.0)
              .toDouble();
    final backups = channel.playbackCandidates.length - 1;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('live-tv-channel-${channel.id}'),
        onTap: opening ? null : onOpen,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (channel.logo != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(7),
                      child: Image.network(
                        channel.logo.toString(),
                        width: 36,
                        height: 36,
                        fit: BoxFit.contain,
                        errorBuilder: (_, error, stack) =>
                            const Icon(Icons.live_tv_rounded, size: 33),
                      ),
                    )
                  else
                    const Icon(Icons.live_tv_rounded, size: 33),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      channel.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    key: ValueKey('live-tv-star-${channel.id}'),
                    tooltip: favorite
                        ? 'Quitar de favoritos'
                        : 'Guardar favorito',
                    icon: Icon(
                      favorite ? Icons.star_rounded : Icons.star_border_rounded,
                    ),
                    onPressed: onFavorite,
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                category.label + (backups > 0 ? ' · $backups respaldos' : ''),
                style: const TextStyle(color: Colors.white60, fontSize: 11),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const Spacer(),
              if (opening)
                const PotvLoadingFlag(width: 72)
              else if (current != null) ...[
                Text(
                  'AHORA · ${current!.title}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                LinearProgressIndicator(value: progress, minHeight: 3),
              ] else
                const Text(
                  'Sin información de programación',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              const SizedBox(height: 7),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      next == null
                          ? 'Toca para reproducir'
                          : 'Después · ${next!.title}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                  const Icon(Icons.play_circle_fill_rounded, size: 22),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyTv extends StatelessWidget {
  const _EmptyTv();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.live_tv_rounded, size: 72),
              SizedBox(height: 20),
              Text(
                'Sin canales disponibles',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 10),
              Text(
                'POTV no pudo actualizar la señal de TV en este momento. '
                'Vuelve a intentar más tarde.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
