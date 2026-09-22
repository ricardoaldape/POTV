import 'package:flutter/material.dart';

import '../../domain/models/media_item.dart';

class MediaDetailScreen extends StatelessWidget {
  final MediaItem item;

  const MediaDetailScreen({
    super.key,
    required this.item,
  });

  @override
  Widget build(BuildContext context) {
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
                  onPressed: null,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text(
                    'Resolver fuentes · siguiente bloque',
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'POTV solo usa TMDB para metadatos. Las fuentes de reproducción se resolverán localmente en el dispositivo.',
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
