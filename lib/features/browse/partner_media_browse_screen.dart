import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/catalog/partner_content_repository.dart';
import '../../domain/models/media_item.dart';
import '../player/media_playback_coordinator.dart';

/// Progressive browse for the private, licensed VOD metadata catalog.
/// Only metadata is fetched here; playback is resolved separately on demand.
class PartnerMediaBrowseScreen extends ConsumerStatefulWidget {
  final MediaType type;
  final String title;

  const PartnerMediaBrowseScreen({
    super.key,
    required this.type,
    required this.title,
  });

  @override
  ConsumerState<PartnerMediaBrowseScreen> createState() =>
      _PartnerMediaBrowseScreenState();
}

class _PartnerMediaBrowseScreenState
    extends ConsumerState<PartnerMediaBrowseScreen> {
  final _items = <MediaItem>[];
  final _seenIds = <int>{};
  bool _loading = false;
  bool _hasMore = true;
  int _offset = 0;
  int _total = 0;
  String? _revision;
  String? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadNext();
    });
  }

  @override
  void didUpdateWidget(covariant PartnerMediaBrowseScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.type != widget.type) {
      _generation++;
      _loading = false;
      _items.clear();
      _seenIds.clear();
      _offset = 0;
      _total = 0;
      _revision = null;
      _hasMore = true;
      _error = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadNext();
      });
    }
  }

  Future<void> _loadNext() async {
    if (_loading || !_hasMore) return;
    final generation = _generation;
    final type = widget.type;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await ref.read(partnerContentRepositoryProvider).loadMediaPage(
            type,
            offset: _offset,
            limit: 200,
          );
      if (!mounted || generation != _generation) return;
      if (_revision != null && _revision != page.revision) {
        // A sync replaced the snapshot mid-pagination. Restart from page 0
        // instead of mixing pages from different revisions.
        setState(() {
          _items.clear();
          _seenIds.clear();
          _offset = 0;
          _total = 0;
          _revision = null;
          _hasMore = true;
          _loading = false;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _loadNext();
        });
        return;
      }
      setState(() {
        _revision = page.revision;
        _total = page.total;
        for (final item in page.items) {
          if (_seenIds.add(item.id)) _items.add(item);
        }
        _offset += page.limit;
        _hasMore = page.hasMore;
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _error = 'No se pudo cargar el catálogo. Revisa tu conexión y acceso.';
        });
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _open(MediaItem item) async {
    if (item.type == MediaType.movie) {
      await MediaPlaybackCoordinator.play(context, ref, item);
    } else if (context.mounted) {
      await context.push('/detail', extra: item);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          if (_loading && _items.isEmpty)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_items.isEmpty && _error != null)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _loadNext,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
            )
          else if (_items.isEmpty && !_hasMore)
            const Expanded(
              child: Center(child: Text('No hay títulos disponibles.')),
            )
          else
            Expanded(
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (notification.metrics.extentAfter < 700 &&
                      !_loading && _hasMore && _error == null) {
                    _loadNext();
                  }
                  return false;
                },
                child: GridView.builder(
                  padding: const EdgeInsets.all(18),
                  gridDelegate:
                      const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 190,
                    childAspectRatio: 0.64,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: _items.length,
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    return Card(
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => _open(item),
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
                                    [item.typeLabel, item.year]
                                        .whereType<String>()
                                        .join(' · '),
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
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${_items.length} de $_total títulos',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                if (_loading)
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (_hasMore)
                  TextButton(
                    onPressed: _loadNext,
                    child: Text(_error == null ? 'Cargar más' : 'Reintentar'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
