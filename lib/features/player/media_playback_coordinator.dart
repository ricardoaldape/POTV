import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/catalog/series_episode_repository.dart';
import '../../data/sources/playback_preparation_service.dart';
import '../../domain/models/media_item.dart';
import '../../domain/models/playback_session.dart';
import 'potv_player_loader.dart';

class MediaPlaybackCoordinator {
  const MediaPlaybackCoordinator._();

  static Future<void> play(
    BuildContext context,
    WidgetRef ref,
    MediaItem item,
  ) async {
    if (item.type == MediaType.movie) {
      return _playResolved(
        context,
        ref,
        item,
        season: null,
        episode: null,
      );
    }

    final selected = await _resolveEpisode(context, item);
    if (selected == null || !context.mounted) return;

    return _playResolved(
      context,
      ref,
      item,
      season: selected.season,
      episode: selected.episode,
    );
  }

  static Future<void> playEpisode(
    BuildContext context,
    WidgetRef ref,
    MediaItem item, {
    int? season,
    required int episode,
  }) {
    return _playResolved(
      context,
      ref,
      item,
      season: season,
      episode: episode,
    );
  }

  static Future<void> _playResolved(
    BuildContext context,
    WidgetRef ref,
    MediaItem item, {
    int? season,
    int? episode,
  }) async {
    if (!context.mounted) return;

    final loading = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const _ResolvingDialog(),
    );

    try {
      final request = PlaybackPreparationRequest.fromMediaItem(
        item,
        season: season,
        episode: episode,
      );
      final prepared =
          await ref.read(playbackPreparationServiceProvider).prepare(request);
      final playbackContext = request.playbackContext;
      final playable = prepared.candidates;

      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      await loading;

      if (playable.isEmpty) {
        if (!context.mounted) return;
        await _showNoSource(context, item);
        return;
      }

      final queues = await _episodeQueues(
        ref,
        item,
        season: season,
        episode: episode,
      );

      final title = switch (item.type) {
        MediaType.movie => item.title,
        MediaType.tv => '${item.title} · T$season E$episode',
        MediaType.anime => '${item.title} · E$episode',
      };

      if (!context.mounted) return;
      await context.push(
        '/player',
        extra: PlaybackSession(
          title: title,
          candidates: playable,
          playbackContext: playbackContext,
          subtitles: prepared.subtitles,
          autoplayQueue: queues.next,
          previousQueue: queues.previous,
        ),
      );
    } catch (error) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      await loading;
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No fue posible reproducir este título. Intenta otra vez.',
          ),
        ),
      );
    }
  }

  static Future<({List<PlaybackContext> previous, List<PlaybackContext> next})>
      _episodeQueues(
    WidgetRef ref,
    MediaItem item, {
    int? season,
    int? episode,
  }) async {
    if (episode == null || item.type == MediaType.movie) {
      return (previous: const <PlaybackContext>[], next: const <PlaybackContext>[]);
    }

    PlaybackContext contextFor(int? seasonValue, int episodeValue) =>
        PlaybackContext(
          mediaId: item.id,
          mediaType: item.mediaTypeName,
          title: item.title,
          externalId: item.externalId,
          season: seasonValue,
          episode: episodeValue,
          poster: item.poster?.toString(),
        );

    if (item.type == MediaType.anime) {
      final count = item.episodeCount;
      final end = count == null ? episode : (episode + 20).clamp(episode, count);
      return (
        previous: [
          for (var e = episode - 1; e >= 1 && e >= episode - 20; e--)
            contextFor(null, e),
        ],
        next: [
          for (var e = episode + 1; e <= end; e++) contextFor(null, e),
        ],
      );
    }

    try {
      // Reuse the detail screen's in-flight/cacheable episode metadata.
      // Do not issue a second network request just to build skip buttons.
      final episodes = await ref.read(seriesEpisodesProvider(item).future);
      final index = episodes.indexWhere(
        (value) => value.season == season && value.episode == episode,
      );
      if (index < 0) return (previous: const <PlaybackContext>[], next: const <PlaybackContext>[]);
      return (
        previous: [
          for (final e in episodes.take(index).toList().reversed.take(20))
            contextFor(e.season, e.episode),
        ],
        next: [
          for (final e in episodes.skip(index + 1).take(20))
            contextFor(e.season, e.episode),
        ],
      );
    } catch (_) {
      return (previous: const <PlaybackContext>[], next: const <PlaybackContext>[]);
    }
  }

  static Future<({int? season, int episode})?> _resolveEpisode(
    BuildContext context,
    MediaItem item,
  ) async {
    if (item.type == MediaType.movie) return null;

    final season = TextEditingController(text: '1');
    final episode = TextEditingController(text: '1');

    final result = await showDialog<({int? season, int episode})>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          item.type == MediaType.anime
              ? 'Elige episodio'
              : 'Elige temporada y episodio',
        ),
        content: Row(
          children: [
            if (item.type == MediaType.tv) ...[
              Expanded(
                child: TextField(
                  controller: season,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Temporada',
                  ),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: TextField(
                controller: episode,
                autofocus: item.type == MediaType.anime,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: item.type == MediaType.anime
                      ? 'Episodio absoluto'
                      : 'Episodio',
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => context.pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () {
              final e = int.tryParse(episode.text.trim());
              final s = item.type == MediaType.tv
                  ? int.tryParse(season.text.trim())
                  : null;

              if (e == null || e < 1) return;
              if (item.type == MediaType.tv && (s == null || s < 1)) return;

              context.pop((season: s, episode: e));
            },
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Reproducir'),
          ),
        ],
      ),
    );

    season.dispose();
    episode.dispose();
    return result;
  }

  static Future<void> _showNoSource(
    BuildContext context,
    MediaItem item,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('No pudimos reproducir este título'),
        content: const Text(
          'Las fuentes disponibles no respondieron en este momento. '
          'Prueba de nuevo más tarde o elige otro título.',
        ),
        actions: [
          FilledButton(
            onPressed: () => dialogContext.pop(),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

}

class _ResolvingDialog extends StatelessWidget {
  const _ResolvingDialog();

  @override
  Widget build(BuildContext context) {
    return const PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            PotvPlayerLoader(size: 46),
            SizedBox(width: 16),
            Expanded(
              child: Text('Preparando reproducción…'),
            ),
          ],
        ),
      ),
    );
  }
}
