import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'data/youtube_client.dart';
import 'data/youtube_providers.dart';
import 'data/youtube_subscription_repository.dart';
import 'domain/youtube_models.dart';

class YoutubeVideoScreen extends ConsumerStatefulWidget {
  final PotvYoutubeVideo initialVideo;

  const YoutubeVideoScreen({super.key, required this.initialVideo});

  @override
  ConsumerState<YoutubeVideoScreen> createState() => _YoutubeVideoScreenState();
}

class _YoutubeVideoScreenState extends ConsumerState<YoutubeVideoScreen> {
  late Future<PotvYoutubeVideo> videoFuture;
  bool resolving = false;

  @override
  void initState() {
    super.initState();
    videoFuture = ref.read(potvYoutubeClientProvider).video(widget.initialVideo.id);
  }

  Future<void> _play() async {
    if (resolving) return;
    setState(() => resolving = true);
    try {
      final session = await ref.read(potvYoutubeClientProvider).playback(widget.initialVideo.id);
      if (!mounted) return;
      await context.push('/player', extra: session);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No pudimos reproducir este video: $error')),
      );
    } finally {
      if (mounted) setState(() => resolving = false);
    }
  }

  Future<void> _toggleSubscription(PotvYoutubeVideo video) async {
    final repository = ref.read(youtubeSubscriptionRepositoryProvider);
    final subscribed = await repository.isSubscribed(video.channelId);
    if (subscribed) {
      await repository.unsubscribe(video.channelId);
    } else {
      String? logo;
      try {
        logo = (await ref.read(potvYoutubeClientProvider).channel(video.channelId)).logoUrl;
      } catch (_) {}
      await repository.subscribe(
        PotvYoutubeSubscription(
          channelId: video.channelId,
          title: video.author,
          logoUrl: logo,
        ),
      );
    }
    ref.invalidate(youtubeSubscriptionsProvider);
    ref.invalidate(youtubeSubscriptionFeedProvider);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('POTV YT')),
      body: FutureBuilder<PotvYoutubeVideo>(
        future: videoFuture,
        initialData: widget.initialVideo,
        builder: (context, snapshot) {
          final video = snapshot.data ?? widget.initialVideo;
          return ListView(
            padding: const EdgeInsets.only(bottom: 30),
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(
                      video.thumbnailUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const ColoredBox(
                        color: Color(0xFF122430),
                        child: Icon(Icons.ondemand_video_rounded, size: 72),
                      ),
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.72)],
                        ),
                      ),
                    ),
                    Center(
                      child: FilledButton.icon(
                        onPressed: resolving ? null : _play,
                        icon: resolving
                            ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.play_arrow_rounded),
                        label: Text(resolving ? 'Preparando…' : 'Reproducir'),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(video.title, style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 8),
                    Text('${video.viewCount} vistas${video.isLive ? ' · EN VIVO' : ''}', style: const TextStyle(color: Colors.white60)),
                    const SizedBox(height: 18),
                    FutureBuilder<bool>(
                      future: ref.read(youtubeSubscriptionRepositoryProvider).isSubscribed(video.channelId),
                      builder: (context, subSnapshot) {
                        final subscribed = subSnapshot.data ?? false;
                        return Card(
                          child: ListTile(
                            onTap: () => context.push('/youtube/channel', extra: video.channelId),
                            leading: const CircleAvatar(child: Icon(Icons.person_rounded)),
                            title: Text(video.author, style: const TextStyle(fontWeight: FontWeight.w800)),
                            subtitle: const Text('Abrir canal'),
                            trailing: FilledButton.tonal(
                              onPressed: () => _toggleSubscription(video),
                              child: Text(subscribed ? 'Suscrito' : 'Suscribirme'),
                            ),
                          ),
                        );
                      },
                    ),
                    if (video.description.trim().isNotEmpty) ...[
                      const SizedBox(height: 18),
                      const Text('Descripción', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 8),
                      SelectableText(video.description, style: const TextStyle(color: Colors.white70, height: 1.45)),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
