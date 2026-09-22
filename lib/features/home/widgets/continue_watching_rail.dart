import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../domain/models/playback_history_entry.dart';

class ContinueWatchingRail extends StatelessWidget {
  final List<PlaybackHistoryEntry> entries;
  final ValueChanged<PlaybackHistoryEntry> onResume;

  const ContinueWatchingRail({
    super.key,
    required this.entries,
    required this.onResume,
  });

  @override
  Widget build(BuildContext context) {
    final visible = entries.take(12).toList(growable: false);
    if (visible.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            'Continuar viendo',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.3,
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 170,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            scrollDirection: Axis.horizontal,
            itemCount: visible.length,
            separatorBuilder: (context, index) =>
                const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final entry = visible[index];
              return _ContinueCard(
                entry: entry,
                onTap: () => onResume(entry),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ContinueCard extends StatefulWidget {
  final PlaybackHistoryEntry entry;
  final VoidCallback onTap;

  const _ContinueCard({
    required this.entry,
    required this.onTap,
  });

  @override
  State<_ContinueCard> createState() => _ContinueCardState();
}

class _ContinueCardState extends State<_ContinueCard> {
  bool focused = false;

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final episode = entry.episode == null
        ? null
        : entry.season == null
            ? 'E${entry.episode}'
            : 'T${entry.season} E${entry.episode}';

    return AnimatedScale(
      scale: focused ? 1.035 : 1,
      duration: const Duration(milliseconds: 160),
      child: SizedBox(
        width: 260,
        child: Material(
          color: PotvTheme.surface,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onFocusChange: (value) => setState(() => focused = value),
            onTap: widget.onTap,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (entry.poster != null)
                  Image.network(
                    entry.poster!,
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                    errorBuilder: (context, error, stack) =>
                        const ColoredBox(color: PotvTheme.surfaceAlt),
                  )
                else
                  const ColoredBox(color: PotvTheme.surfaceAlt),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Color(0x33000000),
                        Color(0xF0000000),
                      ],
                      stops: [0.28, 0.52, 1],
                    ),
                  ),
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 13,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                      if (episode != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          episode,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: entry.progress,
                        minHeight: 4,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: focused
                          ? PotvTheme.cyan
                          : Colors.black.withValues(alpha: 0.68),
                    ),
                    child: Icon(
                      Icons.play_arrow_rounded,
                      color: focused ? PotvTheme.background : Colors.white,
                    ),
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
