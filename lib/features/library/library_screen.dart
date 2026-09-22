import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/history/playback_history_repository.dart';
import '../../domain/models/media_item.dart';
import '../../domain/models/playback_history_entry.dart';
import '../player/media_playback_coordinator.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  late Future<List<PlaybackHistoryEntry>> historyFuture;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    historyFuture = const PlaybackHistoryRepository().all();
  }

  MediaType? _mediaType(String value) {
    return switch (value) {
      'movie' => MediaType.movie,
      'tv' => MediaType.tv,
      'anime' => MediaType.anime,
      _ => null,
    };
  }

  MediaItem? _itemFromHistory(PlaybackHistoryEntry history) {
    final type = _mediaType(history.mediaType);
    if (type == null || history.mediaId <= 0) return null;

    return MediaItem(
      id: history.mediaId,
      type: type,
      title: history.title,
      poster: history.poster == null ? null : Uri.tryParse(history.poster!),
    );
  }

  Future<void> _resume(PlaybackHistoryEntry history) async {
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

    if (!mounted) return;
    setState(_reload);
  }

  Future<void> _openDetails(PlaybackHistoryEntry history) async {
    final item = _itemFromHistory(history);
    if (item == null) return;
    await context.push('/detail', extra: item);
    if (!mounted) return;
    setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi lista'),
      ),
      body: FutureBuilder<List<PlaybackHistoryEntry>>(
        future: historyFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final entries = snapshot.data ?? const [];
          if (entries.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.history_rounded, size: 64),
                    SizedBox(height: 16),
                    Text(
                      'Aún no hay historial',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Cuando reproduzcas algo, POTV guardará localmente dónde te quedaste.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white60),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(18),
            children: [
              const Text(
                'Continuar viendo',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 14),
              for (final entry in entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _HistoryCard(
                    entry: entry,
                    onResume: () => _resume(entry),
                    onDetails: () => _openDetails(entry),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final PlaybackHistoryEntry entry;
  final Future<void> Function() onResume;
  final Future<void> Function() onDetails;

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
            ? 'E${entry.episode}'
            : 'T${entry.season} E${entry.episode}';

    return Card(
      child: InkWell(
        onTap: () async => onResume(),
        onLongPress: () async => onDetails(),
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
                          errorBuilder: (context, error, stack) =>
                              const ColoredBox(
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
                    const SizedBox(height: 6),
                    Text(
                      '${(entry.progress * 100).round()}% visto',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: () async => onResume(),
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: const Text('Continuar'),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: 'Detalles',
                          onPressed: () async => onDetails(),
                          icon: const Icon(Icons.info_outline_rounded),
                        ),
                      ],
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
