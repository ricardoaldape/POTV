import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/history/media_favorites_repository.dart';
import '../../data/history/playback_history_repository.dart';
import '../../domain/models/media_item.dart';
import '../../domain/models/playback_history_entry.dart';
import '../player/media_playback_coordinator.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  MediaType? _mediaType(String value) => switch (value) {
        'movie' => MediaType.movie,
        'tv' => MediaType.tv,
        'anime' => MediaType.anime,
        _ => null,
      };

  MediaItem? _itemFromHistory(PlaybackHistoryEntry history) {
    final type = _mediaType(history.mediaType);
    if (type == null || history.mediaId <= 0) return null;
    return MediaItem(
      id: history.mediaId,
      type: type,
      title: history.title,
      externalId: history.externalId,
      poster: history.poster == null ? null : Uri.tryParse(history.poster!),
    );
  }

  Future<void> _resume(
    BuildContext context,
    WidgetRef ref,
    PlaybackHistoryEntry history,
  ) async {
    final item = _itemFromHistory(history);
    if (item == null) return;
    if (history.episode != null) {
      await MediaPlaybackCoordinator.playEpisode(
        context,
        ref,
        item,
        season: history.season,
        episode: history.episode!,
      );
    } else {
      await MediaPlaybackCoordinator.play(context, ref, item);
    }
    ref.invalidate(playbackHistoryProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites =
        ref.watch(mediaFavoritesProvider).asData?.value ?? const <MediaItem>[];
    final history =
        ref.watch(playbackHistoryProvider).asData?.value ??
            const <PlaybackHistoryEntry>[];

    return Scaffold(
      appBar: AppBar(title: const Text('Mi lista')),
      body: favorites.isEmpty && history.isEmpty
          ? const _EmptyLibrary()
          : ListView(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 40),
              children: [
                if (favorites.isNotEmpty) ...[
                  const _Heading(
                    title: 'Favoritos',
                    subtitle: 'Guardados en este perfil',
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 190,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: favorites.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                      itemBuilder: (context, index) {
                        final item = favorites[index];
                        return _FavoriteCard(
                          item: item,
                          onTap: () => context.push('/detail', extra: item),
                          onRemove: () async {
                            await const MediaFavoritesRepository().toggle(item);
                            ref.invalidate(mediaFavoritesProvider);
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 26),
                ],
                if (history.isNotEmpty) ...[
                  const _Heading(
                    title: 'Continuar viendo',
                    subtitle: 'Tu progreso de este perfil',
                  ),
                  const SizedBox(height: 12),
                  for (final entry in history)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _HistoryCard(
                        entry: entry,
                        onResume: () => _resume(context, ref, entry),
                        onDetails: () {
                          final item = _itemFromHistory(entry);
                          if (item != null) context.push('/detail', extra: item);
                        },
                      ),
                    ),
                ],
              ],
            ),
    );
  }
}

class _Heading extends StatelessWidget {
  final String title;
  final String subtitle;
  const _Heading({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 3),
          Text(subtitle, style: const TextStyle(color: Colors.white60)),
        ],
      );
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary();

  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.favorite_border_rounded, size: 64),
              SizedBox(height: 16),
              Text(
                'Tu lista está vacía',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
              ),
              SizedBox(height: 8),
              Text(
                'Agrega favoritos o comienza a reproducir algo.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white60),
              ),
            ],
          ),
        ),
      );
}

class _FavoriteCard extends StatelessWidget {
  final MediaItem item;
  final VoidCallback onTap;
  final Future<void> Function() onRemove;

  const _FavoriteCard({
    required this.item,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 118,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: InkWell(
                      onTap: onTap,
                      borderRadius: BorderRadius.circular(12),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: item.poster == null
                            ? const ColoredBox(
                                color: Color(0xFF122430),
                                child: Icon(Icons.movie_outlined),
                              )
                            : Image.network(
                                item.poster.toString(),
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    const ColoredBox(
                                  color: Color(0xFF122430),
                                  child: Icon(Icons.movie_outlined),
                                ),
                              ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: IconButton.filledTonal(
                      tooltip: 'Quitar',
                      onPressed: () async => onRemove(),
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      );
}

class _HistoryCard extends StatelessWidget {
  final PlaybackHistoryEntry entry;
  final Future<void> Function() onResume;
  final VoidCallback onDetails;

  const _HistoryCard({
    required this.entry,
    required this.onResume,
    required this.onDetails,
  });

  @override
  Widget build(BuildContext context) {
    final episodeLabel = entry.episode == null
        ? null
        : entry.season == null
            ? 'E' + entry.episode.toString()
            : 'T' +
                entry.season.toString() +
                ' E' +
                entry.episode.toString();

    return Card(
      child: InkWell(
        onTap: () async => onResume(),
        onLongPress: onDetails,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 92,
                  height: 118,
                  child: entry.poster == null
                      ? const ColoredBox(
                          color: Color(0xFF122430),
                          child: Icon(Icons.movie_outlined),
                        )
                      : Image.network(
                          entry.poster!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const ColoredBox(
                            color: Color(0xFF122430),
                            child: Icon(Icons.movie_outlined),
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
                      entry.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (episodeLabel != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        episodeLabel,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                    const SizedBox(height: 10),
                    LinearProgressIndicator(
                      value: entry.progress,
                      minHeight: 5,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    const SizedBox(height: 10),
                    FilledButton.tonalIcon(
                      onPressed: () async => onResume(),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Continuar'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
