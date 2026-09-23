import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../../../domain/models/playback_session.dart';
import '../../../domain/models/stream_candidate.dart';
import '../domain/youtube_models.dart';

final potvYoutubeClientProvider = Provider<PotvYoutubeClient>((ref) {
  final client = PotvYoutubeClient();
  ref.onDispose(client.close);
  return client;
});

class PotvYoutubeClient {
  final YoutubeExplode _yt = YoutubeExplode();

  void close() => _yt.close();

  Future<List<PotvYoutubeVideo>> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    final results = await _yt.search.search(trimmed);
    return results.map(_mapVideo).toList(growable: false);
  }

  Future<PotvYoutubeVideo> video(String id) async {
    return _mapVideo(await _yt.videos.get(id));
  }

  Future<PotvYoutubeChannel> channel(String id) async {
    final value = await _yt.channels.get(id);
    return PotvYoutubeChannel(
      id: value.id.value,
      title: value.title,
      logoUrl: value.logoUrl,
      bannerUrl: value.bannerUrl,
      subscribersCount: value.subscribersCount,
    );
  }

  Future<List<PotvYoutubeVideo>> uploads(
    String channelId, {
    int limit = 12,
  }) async {
    final values = await _yt.channels.getUploads(channelId).take(limit).toList();
    return values.map(_mapVideo).toList(growable: false);
  }

  Future<List<PotvYoutubeVideo>> subscriptionFeed(
    List<PotvYoutubeSubscription> subscriptions, {
    int perChannel = 5,
  }) async {
    if (subscriptions.isEmpty) return const [];
    final batches = await Future.wait([
      for (final subscription in subscriptions.take(24))
        uploads(subscription.channelId, limit: perChannel)
            .catchError((_) => <PotvYoutubeVideo>[]),
    ]);
    final videos = [for (final batch in batches) ...batch];
    videos.sort((a, b) {
      final ad = a.uploadDate ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bd = b.uploadDate ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bd.compareTo(ad);
    });
    return videos;
  }

  Future<PlaybackSession> playback(String videoId) async {
    final metadata = await _yt.videos.get(videoId);

    if (metadata.isLive) {
      final liveUrl = await _yt.videos.streams.getHttpLiveStreamUrl(metadata.id);
      return PlaybackSession(
        title: metadata.title,
        isLive: true,
        candidates: [
          StreamCandidate(
            id: 'yt:${metadata.id.value}:live',
            label: 'YouTube · En vivo',
            uri: Uri.parse(liveUrl),
            quality: 'Auto',
          ),
        ],
      );
    }

    final manifest = await _yt.videos.streams.getManifest(metadata.id);
    final candidates = <StreamCandidate>[];

    final audioOnly = manifest.audioOnly.sortByBitrate();
    final audio = audioOnly.isEmpty ? null : audioOnly.first;
    final videoOnly = manifest.videoOnly.sortByBitrate();
    final seenQualities = <String>{};
    for (final stream in videoOnly) {
      if (audio == null) break;
      final quality = stream.qualityLabel;
      if (!seenQualities.add(quality)) continue;
      candidates.add(
        StreamCandidate(
          id: 'yt:${metadata.id.value}:v${stream.tag}',
          label: 'YouTube · $quality',
          uri: stream.url,
          quality: quality,
          externalAudioUri: audio.url,
        ),
      );
      if (candidates.length >= 4) break;
    }

    for (final stream in manifest.muxed.sortByBitrate()) {
      candidates.add(
        StreamCandidate(
          id: 'yt:${metadata.id.value}:m${stream.tag}',
          label: 'YouTube · ${stream.qualityLabel}',
          uri: stream.url,
          quality: stream.qualityLabel,
        ),
      );
    }

    if (candidates.isEmpty) {
      throw StateError('YouTube no devolvió streams reproducibles para este video.');
    }

    return PlaybackSession(
      title: metadata.title,
      candidates: candidates,
    );
  }

  PotvYoutubeVideo _mapVideo(Video video) {
    return PotvYoutubeVideo(
      id: video.id.value,
      title: video.title,
      author: video.author,
      channelId: video.channelId.value,
      thumbnailUrl: video.thumbnails.highResUrl,
      duration: video.duration,
      uploadDate: video.uploadDate,
      viewCount: video.engagement.viewCount,
      isLive: video.isLive,
      description: video.description,
    );
  }
}
