import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/sources/http_source_resolver.dart';
import '../../domain/models/media_item.dart';
import '../../domain/models/playback_session.dart';
import '../../domain/services/stream_candidate_ranker.dart';

class MediaPlaybackCoordinator {
  static const _ranker = StreamCandidateRanker();

  const MediaPlaybackCoordinator._();

  static Future<void> play(
    BuildContext context,
    WidgetRef ref,
    MediaItem item,
  ) async {
    final episode = await _resolveEpisode(context, item);
    if (episode == null && item.type != MediaType.movie) return;

    if (!context.mounted) return;

    final loading = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const _ResolvingDialog(),
    );

    try {
      final candidates = await ref.read(httpSourceResolverProvider).resolve(
            mediaType: item.mediaTypeName,
            mediaId: item.id.toString(),
            season: episode?.season,
            episode: episode?.episode,
          );

      final ranked = _ranker.rank(candidates);

      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      await loading;

      if (ranked.isEmpty) {
        if (!context.mounted) return;
        await _showNoSource(context, item);
        return;
      }

      final title = switch (item.type) {
        MediaType.movie => item.title,
        MediaType.tv =>
          '${item.title} · T${episode!.season} E${episode.episode}',
        MediaType.anime => '${item.title} · E${episode!.episode}',
      };

      if (!context.mounted) return;
      await context.push(
        '/player',
        extra: PlaybackSession(
          title: title,
          candidates: ranked,
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
          'Tus fuentes locales no devolvieron una reproducción disponible para ${item.title}.',
        ),
        actions: [
          TextButton(
            onPressed: () => context.pop(),
            child: const Text('Cerrar'),
          ),
          TextButton.icon(
            onPressed: () {
              context.pop();
              context.push('/detail', extra: item);
            },
            icon: const Icon(Icons.info_outline),
            label: const Text('Más información'),
          ),
          FilledButton.icon(
            onPressed: () {
              context.pop();
              context.push('/sources');
            },
            icon: const Icon(Icons.hub_outlined),
            label: const Text('Fuentes'),
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
