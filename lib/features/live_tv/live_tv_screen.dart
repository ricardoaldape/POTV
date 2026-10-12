import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/catalog/partner_content_repository.dart';
import '../../data/live_tv/built_in_live_sources.dart';
import '../../domain/services/live_tv_organizer.dart';
import '../../data/live_tv/live_tv_favorites.dart';
import '../../data/live_tv/live_tv_repository.dart';
import '../../domain/models/epg_program.dart';
import '../../domain/models/live_channel.dart';
import '../../domain/models/playback_session.dart';

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
    _partnerRefreshTimer ??= Timer.periodic(
      const Duration(minutes: 2),
      (_) {
        if (mounted) ref.invalidate(partnerContentProvider);
      },
    );
    _guideClock ??= Timer.periodic(
      const Duration(minutes: 1),
      (_) {
        if (mounted) setState(() => _guideNow = DateTime.now());
      },
    );
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
    var channel = selected;
    if (selected.id.startsWith('partner:')) {
      setState(() => _openingChannelId = selected.id);
      try {
        // Signed partner URLs may expire while the user browses the grid.
        // Resolve the latest catalog immediately before opening a channel.
        final snapshot = await ref.read(partnerContentRepositoryProvider)
            .load(forceRefresh: true);
        if (!mounted) return;
        final candidates = [...snapshot.channels, ...snapshot.sportsChannels]
            .where((item) => item.id == selected.id);
        if (candidates.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Este canal ya no está disponible en el catálogo.'),
            ),
          );
          ref.invalidate(partnerContentProvider);
          return;
        }
        channel = candidates.first;
        ref.invalidate(partnerContentProvider);
      } finally {
        if (mounted) setState(() => _openingChannelId = null);
      }
    }
    if (!mounted) return;
    context.push(
      '/player',
      extra: PlaybackSession(
        title: channel.name,
        candidates: channel.playbackCandidates,
        isLive: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final channelsState = ref.watch(liveChannelsProvider);
    final partnerState = ref.watch(partnerContentProvider);
    final sportsState = ref.watch(builtInSportsChannelsProvider);
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
      local: channelsState.asData?.value ?? const <LiveChannel>[],
      partnerSports: partner?.sportsChannels ?? const <LiveChannel>[],
      publicSports: sportsState.asData?.value ?? const <LiveChannel>[],
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
    final loading = channelsState.isLoading ||
        partnerState.isLoading || sportsState.isLoading;
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
              compact ? 16 : 24, 12, compact ? 16 : 24, 8,
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
                    onSelected: (value) => setState(() => favoritesOnly = value),
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
          if (loading) const LinearProgressIndicator(minHeight: 2),
          if (channels.isNotEmpty &&
              (channelsState.hasError || sportsState.hasError))
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 6, 20, 2),
              child: Text(
                'Una fuente no respondió; mostramos los canales disponibles.',
                style: TextStyle(color: Colors.orangeAccent, fontSize: 12),
              ),
            ),
          Expanded(
            child: channels.isEmpty && loading
                ? const Center(child: CircularProgressIndicator())
                : channels.isEmpty
                    ? const _EmptyTv()
                    : onlyFavorites.isEmpty
                        ? const Center(
                            child: Text('No hay canales con ese filtro.'),
                          )
                        : GridView.builder(
                            key: const ValueKey('live-tv-channel-grid'),
                            padding: EdgeInsets.fromLTRB(
                              compact ? 12 : 20, 12,
                              compact ? 12 : 20, 24,
                            ),
                            gridDelegate:
                                SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: compact ? 360 : 340,
                              mainAxisExtent: 192,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                            ),
                            itemCount: onlyFavorites.length,
                            itemBuilder: (context, index) {
                              final channel = onlyFavorites[index];
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
    return (epg != null && epg.isNotEmpty &&
            favorites.contains('epg:$epg')) ||
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
    final progress = current == null ||
            !current!.endsAt.isAfter(current!.startsAt)
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
                    tooltip: favorite ? 'Quitar de favoritos' : 'Guardar favorito',
                    icon: Icon(favorite
                        ? Icons.star_rounded : Icons.star_border_rounded),
                    onPressed: onFavorite,
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                category.label +
                    (backups > 0 ? ' · $backups respaldos' : ''),
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 11,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const Spacer(),
              if (opening)
                const LinearProgressIndicator(minHeight: 3)
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
                      next == null ? 'Toca para reproducir' :
                          'Después · ${next!.title}',
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
    return const Center(
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
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
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
