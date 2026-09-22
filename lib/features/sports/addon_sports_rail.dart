import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/sources/stream_candidate_probe.dart';
import '../../data/sports/addon_sports_repository.dart';
import '../../domain/models/addon_sports_item.dart';
import '../../domain/models/playback_session.dart';
import '../../domain/services/stream_candidate_ranker.dart';

class AddonSportsRail extends ConsumerWidget {
  final List<AddonSportsItem> items;

  const AddonSportsRail({
    super.key,
    required this.items,
  });

  Future<void> _play(
    BuildContext context,
    WidgetRef ref,
    AddonSportsItem item,
  ) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
            SizedBox(width: 16),
            Expanded(child: Text('Buscando servidores del evento…')),
          ],
        ),
      ),
    );

    final streams =
        await ref.read(addonSportsRepositoryProvider).streamsFor(item);
    final ranked = const StreamCandidateRanker().rank(streams);
    final playable = ranked.isEmpty
        ? ranked
        : await ref.read(streamCandidateProbeProvider).preferReachable(ranked);

    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    if (playable.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'El addon ${item.addon.name} no devolvió un servidor reproducible para este evento.',
          ),
        ),
      );
      return;
    }

    context.push(
      '/player',
      extra: PlaybackSession(
        title: item.name,
        candidates: playable,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visible = items.take(30).toList(growable: false);
    if (visible.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 188,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: visible.length,
        separatorBuilder: (context, index) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final item = visible[index];
          return SizedBox(
            width: 286,
            child: Card(
              child: InkWell(
                onTap: () => _play(context, ref, item),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (item.poster != null)
                      Image.network(
                        item.poster.toString(),
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stack) =>
                            const SizedBox.shrink(),
                      ),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color(0x22000000),
                            Color(0x66000000),
                            Color(0xF2000000),
                          ],
                          stops: [0, 0.48, 1],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 12,
                      right: 12,
                      top: 10,
                      child: Row(
                        children: [
                          if (item.isLive)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.redAccent,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: const Text(
                                'EN VIVO',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          const Spacer(),
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.65),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.play_arrow_rounded),
                          ),
                        ],
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
                            item.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            [
                              item.genre,
                              item.addon.name,
                            ].whereType<String>().join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
