import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/catalog/anilist_repository.dart';
import '../../data/catalog/tmdb_repository.dart';
import '../../domain/models/media_item.dart';
import '../player/media_playback_coordinator.dart';

class GenreBrowseRequest {
  final MediaType type;
  final String title;
  final int? tmdbGenreId;
  final String? anilistGenre;

  const GenreBrowseRequest({
    required this.type,
    required this.title,
    this.tmdbGenreId,
    this.anilistGenre,
  });
}

class GenreBrowseScreen extends ConsumerWidget {
  final GenreBrowseRequest request;

  const GenreBrowseScreen({
    super.key,
    required this.request,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<MediaItem>> state;

    if (request.type == MediaType.anime) {
      final genre = request.anilistGenre;
      state = genre == null
          ? const AsyncData<List<MediaItem>>([])
          : ref.watch(animeGenreProvider(genre));
    } else {
      final genreId = request.tmdbGenreId;
      state = genreId == null
          ? const AsyncData<List<MediaItem>>([])
          : ref.watch(
              homeGenreProvider(
                (type: request.type, genreId: genreId),
              ),
            );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(request.title),
      ),
      body: state.when(
        loading: () => const Center(
          child: CircularProgressIndicator(),
        ),
        error: (error, stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'No pudimos cargar esta categoría.\n$error',
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (items) {
          if (items.isEmpty) {
            return const Center(
              child: Text('No hay títulos disponibles en esta categoría.'),
            );
          }

          return GridView.builder(
            padding: const EdgeInsets.all(18),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 190,
              childAspectRatio: 0.60,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return Card(
                child: InkWell(
                  onTap: () async {
                    if (item.type == MediaType.movie) {
                      await MediaPlaybackCoordinator.play(
                        context,
                        ref,
                        item,
                      );
                    } else if (context.mounted) {
                      await context.push('/detail', extra: item);
                    }
                  },
                  onLongPress: () =>
                      context.push('/detail', extra: item),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: item.poster == null
                            ? const ColoredBox(
                                color: Color(0xFF122430),
                                child: Icon(Icons.movie_outlined, size: 48),
                              )
                            : Image.network(
                                item.poster.toString(),
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stack) =>
                                    const ColoredBox(
                                  color: Color(0xFF122430),
                                  child: Icon(Icons.broken_image_outlined),
                                ),
                              ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              [
                                item.typeLabel,
                                item.year,
                              ].whereType<String>().join(' · '),
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.white60,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
