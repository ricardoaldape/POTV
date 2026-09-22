import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/catalog/tmdb_repository.dart';
import '../../domain/models/media_item.dart';
import '../player/media_playback_coordinator.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final controller = TextEditingController();
  Timer? debounce;
  String query = '';

  @override
  void dispose() {
    debounce?.cancel();
    controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      setState(() => query = value.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(mediaSearchProvider(query));

    return Scaffold(
      appBar: AppBar(title: const Text('Buscar')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(18),
            child: TextField(
              controller: controller,
              autofocus: true,
              onChanged: _onChanged,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Película o serie',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(
            child: query.length < 2
                ? const _SearchHint()
                : results.when(
                    data: (items) => _ResultGrid(
                      items: items,
                      onPlay: (item) {
                        if (item.type == MediaType.movie) {
                          return MediaPlaybackCoordinator.play(
                            context,
                            ref,
                            item,
                          );
                        }
                        return context.push('/detail', extra: item);
                      },
                    ),
                    loading: () => const Center(
                      child: CircularProgressIndicator(),
                    ),
                    error: (error, stack) => Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          error.toString(),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _SearchHint extends StatelessWidget {
  const _SearchHint();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Busca películas y series. POTV usa catálogos externos únicamente para metadatos.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white60),
        ),
      ),
    );
  }
}

class _ResultGrid extends StatelessWidget {
  final List<MediaItem> items;
  final Future<void> Function(MediaItem) onPlay;

  const _ResultGrid({
    required this.items,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Center(child: Text('Sin resultados.'));
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
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
            onTap: () async => onPlay(item),
            onLongPress: () => context.push('/detail', extra: item),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: item.poster == null
                      ? const ColoredBox(
                          color: Color(0xFF162128),
                          child: Icon(Icons.movie_outlined, size: 52),
                        )
                      : Image.network(
                          item.poster.toString(),
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stack) =>
                              const ColoredBox(
                            color: Color(0xFF162128),
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
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [
                          item.typeLabel,
                          item.year,
                        ].whereType<String>().join(' · '),
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 12,
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
  }
}
