import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../domain/models/live_channel.dart';
import '../../domain/models/playback_session.dart';

class SportsChannelRail extends StatelessWidget {
  final List<LiveChannel> channels;

  const SportsChannelRail({
    super.key,
    required this.channels,
  });

  @override
  Widget build(BuildContext context) {
    final visible = channels.take(18).toList(growable: false);

    return SizedBox(
      height: 118,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: visible.length,
        separatorBuilder: (context, index) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final channel = visible[index];
          return SizedBox(
            width: 168,
            child: Card(
              child: InkWell(
                onTap: () => context.push(
                  '/player',
                  extra: PlaybackSession(
                    title: channel.name,
                    candidates: [channel.stream],
                    isLive: true,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.live_tv_rounded),
                          Spacer(),
                          Icon(Icons.play_arrow_rounded),
                        ],
                      ),
                      const Spacer(),
                      Text(
                        channel.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
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
