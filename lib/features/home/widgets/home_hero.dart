import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_theme.dart';
import '../../../domain/models/media_item.dart';

class HomeHero extends StatelessWidget {
  final MediaItem item;
  final Future<void> Function() onPlay;

  const HomeHero({
    super.key,
    required this.item,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= 900;

    return SizedBox(
      height: wide ? 470 : 360,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (item.backdrop != null)
            Image.network(
              item.backdrop.toString(),
              fit: BoxFit.cover,
              alignment: Alignment.centerRight,
              errorBuilder: (context, error, stack) =>
                  const ColoredBox(color: PotvTheme.surfaceAlt),
            )
          else
            const ColoredBox(color: PotvTheme.surfaceAlt),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Color(0xFF070B0D),
                  Color(0xE8070B0D),
                  Color(0x66070B0D),
                  Color(0x14070B0D),
                ],
                stops: [0, 0.32, 0.68, 1],
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  Color(0xFF070B0D),
                  Colors.transparent,
                ],
                stops: [0, 0.38],
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                wide ? 42 : 22,
                32,
                wide ? 42 : 22,
                42,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: wide ? 560 : size.width * 0.82,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: PotvTheme.cyan.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: PotvTheme.cyan.withValues(alpha: 0.45),
                        ),
                      ),
                      child: Text(
                        switch (item.type) {
                          MediaType.movie => 'DESTACADA · PELÍCULA',
                          MediaType.tv => 'DESTACADA · SERIE',
                          MediaType.anime => 'DESTACADO · ANIME',
                        },
                        style: const TextStyle(
                          color: PotvTheme.cyan,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: wide ? 42 : 30,
                        height: 0.98,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1.2,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (item.overview?.trim().isNotEmpty == true)
                      Text(
                        item.overview!,
                        maxLines: wide ? 4 : 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: wide ? 16 : 14,
                          height: 1.35,
                          color: Colors.white.withValues(alpha: 0.78),
                        ),
                      ),
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        FilledButton.icon(
                          onPressed: () async => onPlay(),
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: Text(
                            item.type == MediaType.movie
                                ? 'Reproducir'
                                : 'Elegir episodio',
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: () =>
                              context.push('/detail', extra: item),
                          icon: const Icon(Icons.info_outline_rounded),
                          label: const Text('Más información'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
