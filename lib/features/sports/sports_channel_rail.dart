import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../domain/models/live_channel.dart';
import '../../domain/models/playback_session.dart';

/// Horizontal directory shared by category pages and "TV deportiva".
/// Uses a lazy list and deliberately does not truncate the first 18 channels.
class SportsChannelRail extends StatelessWidget {
  final List<LiveChannel> channels;

  const SportsChannelRail({
    super.key,
    required this.channels,
  });

  @override
  Widget build(BuildContext context) {
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
          final alternatives = channel.playbackCandidates.length - 1;

          return SizedBox(
            width: 208,
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                key: ValueKey('sports-channel-${channel.id}'),
                autofocus: false,
                onTap: () => context.push(
                  '/player',
                  extra: PlaybackSession(
                    title: channel.name,
                    candidates: channel.playbackCandidates,
                    isLive: true,
                  ),
                ),
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
