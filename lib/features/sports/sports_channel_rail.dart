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
    final grouped = <String, List<LiveChannel>>{};

    for (final channel in channels) {
      final category = _category(channel);
      grouped.putIfAbsent(category, () => <LiveChannel>[]).add(channel);
    }

    const categoryOrder = <String>[
      'Fútbol',
      'Basket',
      'Motor',
      'Combate',
      'Tenis',
      'Otros deportes',
    ];

    for (final items in grouped.values) {
      items.sort((a, b) => a.name.compareTo(b.name));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final category in categoryOrder)
          if ((grouped[category] ?? const <LiveChannel>[]).isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 8),
              child: Row(
                children: [
                  Icon(_categoryIcon(category), size: 18),
                  const SizedBox(width: 8),
                  Text(
                    category,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${grouped[category]!.length}',
                    style: const TextStyle(color: Colors.white54),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 126,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: grouped[category]!.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final channel = grouped[category]![index];
                  return SizedBox(
                    width: 184,
                    child: Card(
                      clipBehavior: Clip.antiAlias,
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
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 22,
                                backgroundImage: channel.logo == null
                                    ? null
                                    : NetworkImage(channel.logo.toString()),
                                child: channel.logo == null
                                    ? const Icon(Icons.live_tv_rounded)
                                    : null,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      channel.name,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    if (channel.group != null) ...[
                                      const SizedBox(height: 3),
                                      Text(
                                        channel.group!,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white54,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const Icon(Icons.play_arrow_rounded),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
      ],
    );
  }

  String _category(LiveChannel channel) {
    final text = '${channel.group ?? ''} ${channel.name}'.toLowerCase();

    if (_containsAny(text, const [
      'futbol',
      'fútbol',
      'soccer',
      'football',
      'fifa',
      'liga',
    ])) {
      return 'Fútbol';
    }
    if (_containsAny(text, const ['basket', 'nba'])) return 'Basket';
    if (_containsAny(text, const [
      'motor',
      'formula',
      'f1',
      'racing',
      'motogp',
    ])) {
      return 'Motor';
    }
    if (_containsAny(text, const [
      'mma',
      'ufc',
      'boxing',
      'boxeo',
      'fight',
    ])) {
      return 'Combate';
    }
    if (_containsAny(text, const ['tennis', 'tenis'])) return 'Tenis';
    return 'Otros deportes';
  }

  bool _containsAny(String text, List<String> values) {
    return values.any(text.contains);
  }

  IconData _categoryIcon(String category) {
    return switch (category) {
      'Fútbol' => Icons.sports_soccer_rounded,
      'Basket' => Icons.sports_basketball_rounded,
      'Motor' => Icons.sports_motorsports_rounded,
      'Combate' => Icons.sports_mma_rounded,
      'Tenis' => Icons.sports_tennis_rounded,
      _ => Icons.sports_rounded,
    };
  }
}
