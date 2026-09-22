import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_theme.dart';
import '../../../domain/models/media_item.dart';

class MediaRail extends StatelessWidget {
  final String title;
  final List<MediaItem> items;

  const MediaRail({
    super.key,
    required this.title,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 246,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (context, index) =>
                const SizedBox(width: 12),
            itemBuilder: (context, index) => PotvMediaCard(
              item: items[index],
            ),
          ),
        ),
      ],
    );
  }
}

class PotvMediaCard extends StatefulWidget {
  final MediaItem item;

  const PotvMediaCard({
    super.key,
    required this.item,
  });

  @override
  State<PotvMediaCard> createState() => _PotvMediaCardState();
}

class _PotvMediaCardState extends State<PotvMediaCard> {
  bool focused = false;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final targetWidth = wide && focused ? 300.0 : 154.0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      width: targetWidth,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onFocusChange: (value) {
            if (focused == value) return;
            setState(() => focused = value);
          },
          onTap: () => context.push('/detail', extra: widget.item),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: focused ? PotvTheme.cyan : Colors.white12,
                width: focused ? 2 : 1,
              ),
              boxShadow: focused
                  ? [
                      BoxShadow(
                        color: PotvTheme.cyan.withValues(alpha: 0.18),
                        blurRadius: 20,
                        spreadRadius: 1,
                      ),
                    ]
                  : const [],
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _Artwork(
                  item: widget.item,
                  landscape: wide && focused,
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Color(0x24000000),
                        Color(0xE8000000),
                      ],
                      stops: [0.42, 0.65, 1],
                    ),
                  ),
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 12,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.item.title,
                        maxLines: focused ? 2 : 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: focused ? 16 : 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (focused) ...[
                        const SizedBox(height: 4),
                        Text(
                          [
                            widget.item.type == MediaType.movie
                                ? 'Película'
                                : 'Serie',
                            widget.item.year,
                          ].whereType<String>().join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Artwork extends StatelessWidget {
  final MediaItem item;
  final bool landscape;

  const _Artwork({
    required this.item,
    required this.landscape,
  });

  @override
  Widget build(BuildContext context) {
    final uri = landscape && item.backdrop != null
        ? item.backdrop
        : item.poster ?? item.backdrop;

    if (uri == null) {
      return const ColoredBox(
        color: PotvTheme.surfaceAlt,
        child: Center(
          child: Icon(
            Icons.movie_outlined,
            size: 48,
            color: Colors.white38,
          ),
        ),
      );
    }

    return Image.network(
      uri.toString(),
      fit: BoxFit.cover,
      errorBuilder: (context, error, stack) => const ColoredBox(
        color: PotvTheme.surfaceAlt,
        child: Center(
          child: Icon(
            Icons.broken_image_outlined,
            color: Colors.white38,
          ),
        ),
      ),
    );
  }
}
