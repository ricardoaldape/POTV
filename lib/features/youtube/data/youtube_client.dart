import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../../../domain/models/playback_session.dart';
import '../../../domain/models/stream_candidate.dart';
import '../domain/youtube_models.dart';
import 'quickjs_youtube_solver.dart';

const _browserUserAgent =
    'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/153.0.0.0 Mobile Safari/537.36';

final potvYoutubeClientProvider = Provider<PotvYoutubeClient>((ref) {
  final client = PotvYoutubeClient();
  ref.onDispose(client.close);
  return client;
});

class PotvYoutubeClient {
  final YoutubeExplode _yt;
  final Dio _webDio;

  PotvYoutubeClient({
    YoutubeExplode? youtube,
    Dio? webDio,
  })  : _yt = youtube ?? YoutubeExplode(jsSolver: QuickJsYoutubeSolver()),
        _webDio = webDio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 8),
                receiveTimeout: const Duration(seconds: 12),
                headers: const {
                  'User-Agent': _browserUserAgent,
                  'Accept-Language': 'es-MX,es;q=0.9,en;q=0.7',
                },
              ),
            );

  void close() {
    _yt.close();
    _webDio.close(force: true);
  }

  Future<List<PotvYoutubeVideo>> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    Object? primaryError;
    try {
      final results = await _yt.search.search(trimmed);
      final mapped = <PotvYoutubeVideo>[];
      for (final result in results) {
        final video = await _mapSearchResult(result);
        if (video != null) mapped.add(video);
      }
      if (mapped.isNotEmpty) return mapped;
    } catch (error) {
      primaryError = error;
    }

    try {
      final fallback = await _searchFromWeb(trimmed);
      if (fallback.isNotEmpty) return fallback;
    } catch (_) {}

    if (primaryError != null) {
      throw StateError('YouTube no pudo procesar la búsqueda: $primaryError');
    }
    return const [];
  }

  Future<PotvYoutubeVideo?> _mapSearchResult(Video value) async {
    try {
      return _mapVideo(value);
    } catch (_) {
      try {
        return _mapVideo(await _yt.videos.get(value.id));
      } catch (_) {
        return null;
      }
    }
  }

  Future<List<PotvYoutubeVideo>> _searchFromWeb(String query) async {
    final response = await _webDio.get<String>(
      'https://www.youtube.com/results',
      queryParameters: {
        'search_query': query,
        'hl': 'es-419',
      },
      options: Options(responseType: ResponseType.plain),
    );
    final body = response.data ?? '';
    if (body.isEmpty) return const [];

    final ids = <String>[];
    final seen = <String>{};
    final expression = RegExp(
      r'"videoId":"([A-Za-z0-9_-]{11})"',
    );
    for (final match in expression.allMatches(body)) {
      final id = match.group(1);
      if (id == null || !seen.add(id)) continue;
      ids.add(id);
      if (ids.length >= 12) break;
    }

    if (ids.isEmpty) return const [];

    final hydrated = await Future.wait([
      for (final id in ids)
        _yt.videos.get(id).then<PotvYoutubeVideo?>(
              _mapVideo,
              onError: (Object error, StackTrace stackTrace) => null,
            ),
    ]);
    return hydrated.whereType<PotvYoutubeVideo>().toList(growable: false);
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
    final mapped = <PotvYoutubeVideo>[];
    for (final value in values) {
      try {
        mapped.add(_mapVideo(value));
      } catch (_) {
        try {
          mapped.add(_mapVideo(await _yt.videos.get(value.id)));
        } catch (_) {}
      }
    }
    return mapped;
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
    final headers = const {'User-Agent': _browserUserAgent};

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
            headers: headers,
          ),
        ],
      );
    }

    final manifest = await _yt.videos.streams.getManifest(
      metadata.id,
      requireWatchPage: true,
    );
    final candidates = <StreamCandidate>[];
    final seen = <String>{};

    for (final stream in manifest.muxed.sortByBitrate()) {
      final key = 'muxed:${stream.qualityLabel}';
      if (!seen.add(key)) continue;
      candidates.add(
        StreamCandidate(
          id: 'yt:${metadata.id.value}:m${stream.tag}',
          label: 'YouTube · ${stream.qualityLabel}',
          uri: stream.url,
          quality: stream.qualityLabel,
          headers: headers,
        ),
      );
      if (candidates.length >= 3) break;
    }

    final audioOnly = manifest.audioOnly.sortByBitrate();
    final audio = audioOnly.isEmpty ? null : audioOnly.first;
    final videoOnly = manifest.videoOnly.sortByBitrate();
    if (audio != null) {
      var adaptiveCount = 0;
      for (final stream in videoOnly) {
        final quality = stream.qualityLabel;
        final key = 'adaptive:$quality';
        if (!seen.add(key)) continue;
        candidates.add(
          StreamCandidate(
            id: 'yt:${metadata.id.value}:v${stream.tag}',
            label: 'YouTube · $quality',
            uri: stream.url,
            quality: quality,
            headers: headers,
            externalAudioUri: audio.url,
          ),
        );
        adaptiveCount++;
        if (adaptiveCount >= 4) break;
      }
    }

    if (candidates.isEmpty) {
      throw StateError(
        'YouTube no devolvió streams reproducibles para este video.',
      );
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
