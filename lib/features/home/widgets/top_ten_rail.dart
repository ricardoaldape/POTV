import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_theme.dart';
import '../../../domain/models/media_item.dart';

class TopTenRail extends StatelessWidget {
  final String title;
  final List<MediaItem> items;
  final ValueChanged<MediaItem> onPlay;

  const TopTenRail({
    super.key,
    required this.title,
    required this.items,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    final top = items.take(10).toList(growable: false);
    if (top.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.4,
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 230,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            scrollDirection: Axis.horizontal,
            itemCount: top.length,
            separatorBuilder: (context, index) =>
                const SizedBox(width: 12),
            itemBuilder: (context, index) => _TopTenCard(
              rank: index + 1,
              item: top[index],
              onPlay: () => onPlay(top[index]),
            ),
          ),
        ),
      ],
    );
  }
}

class _TopTenCard extends StatefulWidget {
  final int rank;
  final MediaItem item;
  final VoidCallback onPlay;

  const _TopTenCard({
    required this.rank,
    required this.item,
    required this.onPlay,
  });

  @override
  State<_TopTenCard> createState() => _TopTenCardState();
}

class _TopTenCardState extends State<_TopTenCard> {
  bool focused = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: focused ? 1.045 : 1,
      duration: const Duration(milliseconds: 160),
      child: SizedBox(
        width: 210,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              bottom: 2,
              child: Text(
                '${widget.rank}',
                style: TextStyle(
                  fontSize: 150,
                  height: 0.9,
                  fontWeight: FontWeight.w900,
                  shadows: const [
                    Shadow(
                      color: Colors.black54,
                      blurRadius: 8,
                      offset: Offset(2, 3),
                    ),
                  ],
                  foreground: Paint()
                    ..style = PaintingStyle.stroke
                    ..strokeWidth = 3
                    ..color = focused
                        ? PotvTheme.cyan
                        : Colors.white.withValues(alpha: 0.55),
                ),
              ),
            ),
            Positioned(
              left: 78,
              top: 0,
              bottom: 0,
              right: 0,
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(14),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onFocusChange: (value) =>
                      setState(() => focused = value),
                  onTap: widget.onPlay,
                  onLongPress: () =>
                      context.push('/detail', extra: widget.item),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: focused
                            ? PotvTheme.cyan
                            : Colors.white12,
                        width: focused ? 2 : 1,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: widget.item.poster == null
                        ? const ColoredBox(
                            color: PotvTheme.surfaceAlt,
                            child: Icon(Icons.movie_outlined),
                          )
                        : Image.network(
                            widget.item.poster.toString(),
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stack) =>
                                const ColoredBox(
                              color: PotvTheme.surfaceAlt,
                              child: Icon(Icons.broken_image_outlined),
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
