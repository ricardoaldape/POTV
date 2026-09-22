import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/catalog/series_episode_repository.dart';
import '../../data/history/playback_history_repository.dart';
import '../../data/sources/unified_source_resolver.dart';
import '../../domain/models/media_item.dart';
import '../../domain/models/playback_history_entry.dart';
import '../../domain/models/series_episode.dart';
import '../player/media_playback_coordinator.dart';

class MediaDetailScreen extends ConsumerStatefulWidget {
  final MediaItem item;

  const MediaDetailScreen({
    super.key,
    required this.item,
  });

  @override
  ConsumerState<MediaDetailScreen> createState() => _MediaDetailScreenState();
}

class _MediaDetailScreenState extends ConsumerState<MediaDetailScreen> {
  int? selectedSeason;
  late Future<PlaybackHistoryEntry?> historyFuture;

  @override
  void initState() {
    super.initState();
    historyFuture = const PlaybackHistoryRepository().latestForMedia(
      mediaId: widget.item.id,
      mediaType: widget.item.mediaTypeName,
    );

    unawaited(_warmInitialResolution());
    unawaited(
      historyFuture.then((history) async {
        final episode = history?.episode;
        if (episode == null) return;
        await _warmResolution(
          season: history?.season,
          episode: episode,
        );
      }),
    );
  }

  Future<void> _warmInitialResolution() {
    final item = widget.item;
    if (item.type == MediaType.movie) {
      return _warmResolution();
    }
    if (item.type == MediaType.tv) {
      return _warmResolution(season: 1, episode: 1);
    }
    return _warmResolution(episode: 1);
  }

  Future<void> _warmResolution({
    int? season,
    int? episode,
  }) async {
    try {
      await ref.read(unifiedSourceResolverProvider).resolve(
            mediaType: widget.item.mediaTypeName,
            mediaId: widget.item.id.toString(),
            externalId: widget.item.externalId,
            title: widget.item.title,
            year: widget.item.year,
            season: season,
            episode: episode,
          );
    } catch (_) {
      // Warm-up is opportunistic. Play performs the authoritative resolution.
    }
  }

  Future<void> _playMovie() {
    return MediaPlaybackCoordinator.play(context, ref, widget.item);
  }

  Future<void> _playEpisode(SeriesEpisode episode) async {
    await MediaPlaybackCoordinator.playEpisode(
      context,
      ref,
      widget.item,
      season: episode.season,
      episode: episode.episode,
    );
    if (!mounted) return;
    setState(() {
      historyFuture = const PlaybackHistoryRepository().latestForMedia(
        mediaId: widget.item.id,
        mediaType: widget.item.mediaTypeName,
      );
    });
  }

  Future<void> _playHistory(PlaybackHistoryEntry history) async {
    final episode = history.episode;
    if (episode == null) return;

    await MediaPlaybackCoordinator.playEpisode(
      context,
      ref,
      widget.item,
      season: history.season,
      episode: episode,
    );
    if (!mounted) return;
    setState(() {
      historyFuture = const PlaybackHistoryRepository().latestForMedia(
        mediaId: widget.item.id,
        mediaType: widget.item.mediaTypeName,
      );
    });
  }

  Future<void> _playAnimeEpisode(int episode) async {
    await MediaPlaybackCoordinator.playEpisode(
      context,
      ref,
      widget.item,
      episode: episode,
    );
    if (!mounted) return;
    setState(() {
      historyFuture = const PlaybackHistoryRepository().latestForMedia(
        mediaId: widget.item.id,
        mediaType: widget.item.mediaTypeName,
      );
    });
  }

  Future<void> _chooseAnimeEpisode() async {
    final controller = TextEditingController(text: '1');

    final episode = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Elige episodio'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Episodio',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => context.pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () {
              final value = int.tryParse(controller.text.trim());
              if (value == null || value < 1) return;
              context.pop(value);
            },
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Reproducir'),
          ),
        ],
      ),
    );

    controller.dispose();
    if (episode == null || !mounted) return;

    await _playAnimeEpisode(episode);
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 320,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  if (item.backdrop != null)
                    Image.network(
                      item.backdrop.toString(),
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stack) =>
                          const ColoredBox(color: Color(0xFF10171C)),
                    )
                  else
                    const ColoredBox(color: Color(0xFF10171C)),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0x22000000),
                          Color(0xFF071219),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 44),
            sliver: SliverList.list(
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    Chip(label: Text(item.typeLabel)),
                    if (item.year != null) Chip(label: Text(item.year!)),
                    Chip(
                      label: Text(
                        item.type == MediaType.anime
                            ? 'AniList ${item.id}'
                            : 'TMDB ${item.id}',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  item.overview?.trim().isNotEmpty == true
                      ? item.overview!
                      : 'Sin descripción disponible.',
                  style: const TextStyle(
                    fontSize: 16,
                    height: 1.45,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 22),
                FutureBuilder<PlaybackHistoryEntry?>(
                  future: historyFuture,
                  builder: (context, snapshot) {
                    final history = snapshot.data;
                    if (history == null ||
                        history.episode == null ||
                        item.type == MediaType.movie) {
                      return const SizedBox.shrink();
                    }

                    final label = item.type == MediaType.tv
                        ? 'Continuar · T${history.season} E${history.episode}'
                        : 'Continuar · E${history.episode}';

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 18),
                      child: FilledButton.icon(
                        onPressed: () => _playHistory(history),
                        icon: const Icon(Icons.play_circle_fill_rounded),
                        label: Text(label),
                      ),
                    );
                  },
                ),
                if (item.type == MediaType.movie)
                  FilledButton.icon(
                    onPressed: _playMovie,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Reproducir'),
                  ),
                if (item.type == MediaType.anime) ...[
                  const Text(
                    'Episodios',
                    style: TextStyle(
                      fontSize: 25,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (item.episodeCount != null && item.episodeCount! > 0)
                    _AnimeEpisodes(
                      episodeCount: item.episodeCount!,
                      onPlay: _playAnimeEpisode,
                    )
                  else
                    FilledButton.icon(
                      onPressed: _chooseAnimeEpisode,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Elegir episodio'),
                    ),
                ],
                if (item.type == MediaType.tv) ...[
                  const Text(
                    'Episodios',
                    style: TextStyle(
                      fontSize: 25,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _SeriesEpisodes(
                    item: item,
                    selectedSeason: selectedSeason,
                    onSeasonChanged: (value) {
                      setState(() => selectedSeason = value);
                    },
                    onPlay: _playEpisode,
                  ),
                ],
                const SizedBox(height: 18),
                const Text(
                  'POTV recuerda localmente tu avance para continuar después en este dispositivo.',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AnimeEpisodes extends StatefulWidget {
  final int episodeCount;
  final ValueChanged<int> onPlay;

  const _AnimeEpisodes({
    required this.episodeCount,
    required this.onPlay,
  });

  @override
  State<_AnimeEpisodes> createState() => _AnimeEpisodesState();
}

class _AnimeEpisodesState extends State<_AnimeEpisodes> {
  static const pageSize = 50;
  int page = 0;

  @override
  Widget build(BuildContext context) {
    final pageCount = (widget.episodeCount / pageSize).ceil();
    final start = page * pageSize + 1;
    final end = (start + pageSize - 1).clamp(1, widget.episodeCount);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (pageCount > 1) ...[
          Row(
            children: [
              IconButton.filledTonal(
                tooltip: 'Episodios anteriores',
                onPressed: page == 0
                    ? null
                    : () => setState(() => page -= 1),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Expanded(
                child: Text(
                  'Episodios $start–$end de ${widget.episodeCount}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton.filledTonal(
                tooltip: 'Siguientes episodios',
                onPressed: page >= pageCount - 1
                    ? null
                    : () => setState(() => page += 1),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var episode = start; episode <= end; episode++)
              SizedBox(
                width: 68,
                child: FilledButton.tonal(
                  onPressed: () => widget.onPlay(episode),
                  child: Text('$episode'),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _SeriesEpisodes extends ConsumerWidget {
  final MediaItem item;
  final int? selectedSeason;
  final ValueChanged<int> onSeasonChanged;
  final ValueChanged<SeriesEpisode> onPlay;

  const _SeriesEpisodes({
    required this.item,
    required this.selectedSeason,
    required this.onSeasonChanged,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(seriesEpisodesProvider(item));

    return state.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 30),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, stack) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Text(
          'No pudimos cargar la lista de episodios.',
          style: TextStyle(color: Colors.white60),
        ),
      ),
      data: (episodes) {
        if (episodes.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Text(
              'No encontramos episodios para esta serie.',
              style: TextStyle(color: Colors.white60),
            ),
          );
        }

        final seasons = episodes.map((e) => e.season).toSet().toList()..sort();
        final activeSeason = seasons.contains(selectedSeason)
            ? selectedSeason!
            : seasons.first;
        final visible = episodes
            .where((episode) => episode.season == activeSeason)
            .toList(growable: false);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 48,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: seasons.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final season = seasons[index];
                  return ChoiceChip(
                    selected: season == activeSeason,
                    label: Text('Temporada $season'),
                    onSelected: (_) => onSeasonChanged(season),
                  );
                },
              ),
            ),
            const SizedBox(height: 14),
            for (final episode in visible)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _EpisodeCard(
                  episode: episode,
                  onTap: () => onPlay(episode),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _EpisodeCard extends StatelessWidget {
  final SeriesEpisode episode;
  final VoidCallback onTap;

  const _EpisodeCard({
    required this.episode,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 132,
                  height: 76,
                  child: episode.thumbnail == null
                      ? const ColoredBox(
                          color: Color(0xFF142630),
                          child: Icon(Icons.play_circle_outline_rounded),
                        )
                      : Image.network(
                          episode.thumbnail.toString(),
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stack) =>
                              const ColoredBox(
                            color: Color(0xFF142630),
                            child: Icon(Icons.play_circle_outline_rounded),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${episode.code} · ${episode.title}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    if (episode.overview?.trim().isNotEmpty == true) ...[
                      const SizedBox(height: 5),
                      Text(
                        episode.overview!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.play_arrow_rounded),
            ],
          ),
        ),
      ),
    );
  }
}
