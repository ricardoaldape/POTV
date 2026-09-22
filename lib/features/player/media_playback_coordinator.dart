import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/sources/stream_candidate_probe.dart';
import '../../data/sources/unified_source_resolver.dart';
import '../../domain/models/media_item.dart';
import '../../domain/models/playback_session.dart';
import '../../domain/models/stream_candidate.dart';
import '../../domain/services/stream_candidate_ranker.dart';

class MediaPlaybackCoordinator {
  static const _ranker = StreamCandidateRanker();

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
      final candidates = await ref.read(unifiedSourceResolverProvider).resolve(
            mediaType: item.mediaTypeName,
            mediaId: item.id.toString(),
            externalId: item.externalId,
            title: item.title,
            year: item.year,
            season: season,
            episode: episode,
          );

      final inAppCandidates = candidates
          .where((candidate) => candidate.backend != PlaybackBackend.external)
          .toList(growable: false);
      final ranked = _ranker.rank(inAppCandidates);
      final playable = ranked.isEmpty
          ? ranked
          : await ref.read(streamCandidateProbeProvider).preferReachable(ranked);

      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      await loading;

      if (playable.isEmpty) {
        if (!context.mounted) return;
        await _showNoSource(context, item);
        return;
      }

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
          playbackContext: PlaybackContext(
            mediaId: item.id,
            mediaType: item.mediaTypeName,
            title: item.title,
            externalId: item.externalId,
            season: season,
            episode: episode,
            poster: item.poster?.toString(),
          ),
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
            'No pudimos consultar tus fuentes. ${error.toString()}',
          ),
        ),
      );
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
  ) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sin servidor disponible'),
        content: Text(
          'POTV no encontró una reproducción disponible para ${item.title}.',
        ),
        actions: [
          FilledButton(
            onPressed: () => context.pop(),
            child: const Text('Cerrar'),
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
            SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            SizedBox(width: 16),
            Expanded(
              child: Text('Buscando el mejor servidor…'),
            ),
          ],
        ),
      ),
    );
  }
}
