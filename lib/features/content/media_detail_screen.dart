import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/sources/http_source_resolver.dart';
import '../../domain/models/media_item.dart';
import '../../domain/models/playback_session.dart';

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
  bool resolving = false;

  Future<({int season, int episode})?> _askEpisode() async {
    final season = TextEditingController(text: '1');
    final episode = TextEditingController(text: '1');

    final result = await showDialog<({int season, int episode})>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Selecciona episodio'),
        content: Row(
          children: [
            Expanded(
              child: TextField(
                controller: season,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Temporada'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: episode,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Episodio'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => context.pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final s = int.tryParse(season.text.trim());
              final e = int.tryParse(episode.text.trim());
              if (s == null || e == null || s < 1 || e < 1) return;
              context.pop((season: s, episode: e));
            },
            child: const Text('Continuar'),
          ),
        ],
      ),
    );

    season.dispose();
    episode.dispose();
    return result;
  }

  Future<void> _resolveAndPlay() async {
    if (resolving) return;

    int? season;
    int? episode;
    if (widget.item.type == MediaType.tv) {
      final selected = await _askEpisode();
      if (selected == null) return;
      season = selected.season;
      episode = selected.episode;
    }

    setState(() => resolving = true);
    try {
      final candidates = await ref.read(httpSourceResolverProvider).resolve(
            mediaType: widget.item.mediaTypeName,
            mediaId: widget.item.id.toString(),
            season: season,
            episode: episode,
          );

      if (!mounted) return;

      if (candidates.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Tus fuentes locales no devolvieron servidores para este contenido.',
            ),
          ),
        );
        return;
      }

      final title = widget.item.type == MediaType.tv
          ? '${widget.item.title} · T$season E$episode'
          : widget.item.title;

      await context.push(
        '/player',
        extra: PlaybackSession(
          title: title,
          candidates: candidates,
        ),
      );
    } finally {
      if (mounted) setState(() => resolving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 300,
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
                          Color(0xEE070B0D),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(22),
            sliver: SliverList.list(
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    Chip(
                      label: Text(
                        item.type == MediaType.movie ? 'Película' : 'Serie',
                      ),
                    ),
                    if (item.year != null) Chip(label: Text(item.year!)),
                    Chip(label: Text('TMDB ${item.id}')),
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
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: resolving ? null : _resolveAndPlay,
                  icon: resolving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow_rounded),
                  label: Text(
                    resolving
                        ? 'Buscando en tus fuentes…'
                        : item.type == MediaType.movie
                            ? 'Buscar servidores'
                            : 'Elegir episodio y buscar',
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'La consulta se realiza directamente desde este dispositivo a las fuentes configuradas. POTV no recibe la URL ni el resultado.',
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
