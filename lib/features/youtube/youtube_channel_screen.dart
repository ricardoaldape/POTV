import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'data/youtube_client.dart';
import 'data/youtube_providers.dart';
import 'data/youtube_subscription_repository.dart';
import 'domain/youtube_models.dart';
import 'widgets/youtube_video_card.dart';

typedef _ChannelPageData = ({PotvYoutubeChannel channel, List<PotvYoutubeVideo> uploads});

class YoutubeChannelScreen extends ConsumerStatefulWidget {
  final String channelId;

  const YoutubeChannelScreen({super.key, required this.channelId});

  @override
  ConsumerState<YoutubeChannelScreen> createState() => _YoutubeChannelScreenState();
}

class _YoutubeChannelScreenState extends ConsumerState<YoutubeChannelScreen> {
  late Future<_ChannelPageData> future;

  @override
  void initState() {
    super.initState();
    future = _load();
  }

  Future<_ChannelPageData> _load() async {
    final client = ref.read(potvYoutubeClientProvider);
    final channel = await client.channel(widget.channelId);
    final uploads = await client.uploads(widget.channelId, limit: 24);
    return (channel: channel, uploads: uploads);
  }

  Future<void> _toggle(PotvYoutubeChannel channel) async {
    final repo = ref.read(youtubeSubscriptionRepositoryProvider);
    if (await repo.isSubscribed(channel.id)) {
      await repo.unsubscribe(channel.id);
    } else {
      await repo.subscribe(PotvYoutubeSubscription(
        channelId: channel.id,
        title: channel.title,
        logoUrl: channel.logoUrl,
      ));
    }
    ref.invalidate(youtubeSubscriptionsProvider);
    ref.invalidate(youtubeSubscriptionFeedProvider);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Canal')),
      body: FutureBuilder<_ChannelPageData>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || snapshot.data == null) {
            return Center(child: Padding(padding: const EdgeInsets.all(28), child: Text('No pudimos abrir el canal.\n${snapshot.error}', textAlign: TextAlign.center)));
          }
          final data = snapshot.data!;
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Column(
                  children: [
                    if (data.channel.bannerUrl.isNotEmpty)
                      AspectRatio(
                        aspectRatio: 4.5,
                        child: Image.network(data.channel.bannerUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                      ),
                    Padding(
                      padding: const EdgeInsets.all(18),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 34,
                            backgroundImage: data.channel.logoUrl.isEmpty ? null : NetworkImage(data.channel.logoUrl),
                            child: data.channel.logoUrl.isEmpty ? const Icon(Icons.person_rounded) : null,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(data.channel.title, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
                                if (data.channel.subscribersCount != null)
                                  Text('${data.channel.subscribersCount} suscriptores', style: const TextStyle(color: Colors.white60)),
                              ],
                            ),
                          ),
                          FutureBuilder<bool>(
                            future: ref.read(youtubeSubscriptionRepositoryProvider).isSubscribed(data.channel.id),
                            builder: (context, sub) => FilledButton.tonal(
                              onPressed: () => _toggle(data.channel),
                              child: Text(sub.data == true ? 'Suscrito' : 'Suscribirme'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(18, 2, 18, 10),
                      child: Align(alignment: Alignment.centerLeft, child: Text('Videos', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900))),
                    ),
                  ],
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: MediaQuery.sizeOf(context).width >= 1100 ? 4 : MediaQuery.sizeOf(context).width >= 700 ? 3 : 1,
                    childAspectRatio: MediaQuery.sizeOf(context).width >= 700 ? 1.15 : 1.45,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final video = data.uploads[index];
                      return YoutubeVideoCard(video: video, onTap: () => context.push('/youtube/video', extra: video));
                    },
                    childCount: data.uploads.length,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
