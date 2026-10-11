import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
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

  Future<void> _addSource() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Añadir TV'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'URL M3U',
            hintText: 'https://proveedor.example/lista.m3u',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => context.pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => context.pop(controller.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (value != null && value.isNotEmpty) {
      try {
        await ref.read(liveChannelsProvider.notifier).setSource(value);
        if (mounted) {
          setState(() => selectedCategory = LiveTvCategory.all);
          if (ref.read(liveChannelsProvider).hasError) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('No se pudo cargar la lista. Revisa su dirección.'),
            ));
          }
        }
      } on FormatException {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Introduce una URL M3U HTTP(S) válida.'),
          ));
        }
      }
    }
  }

  Future<void> _importPlaylistFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['m3u', 'm3u8', 'txt'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final bytes = result.files.single.bytes;
    if (bytes == null || bytes.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No pudimos leer el archivo.')),
      );
      return;
    }

    final raw = utf8.decode(bytes, allowMalformed: true);
    if (!raw.contains('#EXTM3U')) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El archivo no parece una lista M3U.')),
      );
      return;
    }

    try {
      await ref.read(liveChannelsProvider.notifier).setLocalPlaylist(raw);
      if (mounted) setState(() => selectedCategory = LiveTvCategory.all);
    } on FormatException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('La lista no es válida o supera el tamaño permitido.'),
        ));
      }
    }
  }

  Future<void> _manageSources() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          child: FutureBuilder(
            future: ref.read(liveTvRepositoryProvider).configuredSources(),
            builder: (context, snapshot) {
              final sources = snapshot.data ?? const <({String key, String label})>[];
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Tus listas de TV',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Las fuentes se consultan desde tu dispositivo. '
                    'No mostramos tokens ni direcciones privadas en esta lista.',
                    style: TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 12),
                  if (snapshot.connectionState == ConnectionState.waiting)
                    const Center(child: CircularProgressIndicator()),
                  if (snapshot.connectionState != ConnectionState.waiting &&
                      sources.isEmpty)
                    const Text('No hay listas M3U personalizadas.'),
                  for (final source in sources)
                    ListTile(
                      leading: const Icon(Icons.playlist_play_rounded),
                      title: Text(source.label),
                      subtitle: Text(source.key.startsWith('file:')
                          ? 'Archivo local'
                          : 'Lista remota'),
                      trailing: IconButton(
                        tooltip: 'Eliminar esta lista',
                        icon: const Icon(Icons.delete_outline_rounded),
                        onPressed: () async {
                          final confirmed = await showDialog<bool>(
                            context: sheetContext,
                            builder: (confirmContext) => AlertDialog(
                              title: const Text('Eliminar lista'),
                              content: Text(
                                '¿Quitar ${source.label} de POTV? '
                                'Los demás canales no se modificarán.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(confirmContext, false),
                                  child: const Text('Cancelar'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(confirmContext, true),
                                  child: const Text('Quitar'),
                                ),
                              ],
                            ),
                          );
                          if (confirmed != true) return;
                          await ref.read(liveChannelsProvider.notifier)
                              .removeSource(source.key);
                          if (sheetContext.mounted) {
                            Navigator.pop(sheetContext);
                          }
                        },
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _addEpgSource() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Añadir guía EPG'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'URL XMLTV',
            hintText: 'https://proveedor.example/guide.xml',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => context.pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => context.pop(controller.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (value != null && value.isNotEmpty) {
      await ref.read(epgProgramsProvider.notifier).setSource(value);
    }
  }

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
          PopupMenuButton<String>(
            tooltip: 'Gestionar fuentes de TV',
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (choice) {
              if (choice == 'url') _addSource();
              if (choice == 'file') _importPlaylistFile();
              if (choice == 'epg') _addEpgSource();
              if (choice == 'manage') _manageSources();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'url', child: Text('Añadir lista M3U')),
              PopupMenuItem(value: 'file', child: Text('Importar archivo M3U')),
              PopupMenuItem(value: 'epg', child: Text('Configurar guía EPG')),
              PopupMenuItem(value: 'manage', child: Text('Gestionar mis listas')),
            ],
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
                    ? _EmptyTv(onAdd: _addSource)
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
  final VoidCallback onAdd;
  const _EmptyTv({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.live_tv_rounded, size: 72),
              const SizedBox(height: 20),
              const Text(
                'Sin canales disponibles',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'No pudimos cargar los canales públicos en este momento. También puedes añadir tu propia lista M3U; se guarda y consulta directamente desde este dispositivo.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add),
                label: const Text('Añadir lista M3U'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
