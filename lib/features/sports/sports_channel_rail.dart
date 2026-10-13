import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/sources/stream_candidate_probe.dart';
import '../../domain/models/live_channel.dart';
import '../../domain/services/sports_channel_language.dart';
import '../../domain/models/playback_session.dart';

/// Horizontal directory shared by category pages and "TV deportiva".
/// Uses a lazy list and deliberately does not truncate the first 18 channels.
class SportsChannelRail extends ConsumerWidget {
  final List<LiveChannel> channels;
  final SportsLanguagePreference preferredLanguage;
  static const _language = SportsChannelLanguage();

  const SportsChannelRail({
    super.key,
    required this.channels,
    this.preferredLanguage = SportsLanguagePreference.all,
  });

  Future<void> _play(
    BuildContext context,
    WidgetRef ref,
    LiveChannel channel,
  ) async {
    final ordered = _language.orderedStreams(channel, preferredLanguage);
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
            Expanded(child: Text('Verificando señal…')),
          ],
        ),
      ),
    );

    final playable = await ref.read(streamCandidateProbeProvider).preferReachable(
          ordered,
          dropDeadWhenCertain: true,
        );

    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    if (playable.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Esta señal no está respondiendo. Prueba otro canal o actualiza.',
          ),
        ),
      );
      return;
    }

    context.push(
      '/player',
      extra: PlaybackSession(
        title: channel.name,
        candidates: playable,
        isLive: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (channels.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 150,
      child: ListView.separated(
        primary: false,
        scrollDirection: Axis.horizontal,
        itemCount: channels.length,
        separatorBuilder: (context, index) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final channel = channels[index];
          final ordered = _language.orderedStreams(channel, preferredLanguage);
          final alternatives = ordered.length - 1;
          final spokenLanguage = _language.labelFor(channel);

          return SizedBox(
            width: 208,
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                key: ValueKey('sports-channel-${channel.id}'),
                autofocus: false,
                onTap: () => _play(context, ref, channel),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (channel.logo != null)
                            CircleAvatar(
                              radius: 16,
                              backgroundImage:
                                  NetworkImage(channel.logo.toString()),
                            )
                          else
                            const Icon(Icons.live_tv_rounded, size: 28),
                          const Spacer(),
                          if (spokenLanguage != null)
                            Padding(
                              padding: const EdgeInsets.only(right: 5),
                              child: Text(
                                spokenLanguage,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          const Icon(Icons.play_circle_fill_rounded, size: 24),
                        ],
                      ),
                      const Spacer(),
                      Text(
                        channel.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        alternatives > 0
                            ? '$alternatives señales de respaldo'
                            : channel.group ?? 'TV deportiva',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
