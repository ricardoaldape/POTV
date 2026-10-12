import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/addons/stremio_subtitle_service.dart';
import '../../domain/models/media_item.dart';
import '../../domain/models/playback_session.dart';
import '../../domain/models/stream_candidate.dart';
import '../../domain/services/stream_candidate_ranker.dart';
import '../history/stream_server_health_repository.dart';
import 'stream_candidate_probe.dart';
import 'unified_source_resolver.dart';

final playbackPreparationServiceProvider = Provider<PlaybackPreparationService>((ref) {
  return PlaybackPreparationService(
    resolver: ref.read(unifiedSourceResolverProvider),
    probe: ref.read(streamCandidateProbeProvider),
    subtitleService: ref.read(stremioSubtitleServiceProvider),
  );
});

class PlaybackPreparationRequest {
  final String mediaType;
  final int mediaId;
  final String title;
  final String? externalId;
  final String? year;
  final int? season;
  final int? episode;
  final String? poster;

  const PlaybackPreparationRequest({
    required this.mediaType,
    required this.mediaId,
    required this.title,
    this.externalId,
    this.year,
    this.season,
    this.episode,
    this.poster,
  });

  factory PlaybackPreparationRequest.fromMediaItem(
    MediaItem item, {
    int? season,
    int? episode,
  }) =>
      PlaybackPreparationRequest(
        mediaType: item.mediaTypeName,
        mediaId: item.id,
        title: item.title,
        externalId: item.externalId,
        year: item.year,
        season: season,
        episode: episode,
        poster: item.poster?.toString(),
      );

  PlaybackContext get playbackContext => PlaybackContext(
        mediaId: mediaId,
        mediaType: mediaType,
        title: title,
        externalId: externalId,
        season: season,
        episode: episode,
        poster: poster,
      );

  String get cacheKey => [
        mediaType,
        mediaId,
        externalId ?? '',
        season ?? '',
        episode ?? '',
      ].join(':');
}

class PreparedPlayback {
  final PlaybackPreparationRequest request;
  final List<StreamCandidate> candidates;
  final List<PlaybackSubtitle> subtitles;
  final DateTime preparedAt;

  const PreparedPlayback({
    required this.request,
    required this.candidates,
    this.subtitles = const [],
    required this.preparedAt,
  });
}

/// Resolves, ranks and probes sources once while the detail screen is open.
/// Results live only in memory, expire quickly, and are never written with
/// signed media URLs. Android additionally asks Media3 to buffer 3 seconds of
/// the best headerless native candidate when possible.
class PlaybackPreparationService {
  static const _ttl = Duration(minutes: 2);
  static const _maxEntries = 8;
  static const _preloadChannel = MethodChannel('potv/media3_preload');
  static const _ranker = StreamCandidateRanker();

  final UnifiedSourceResolver resolver;
  final StreamCandidateProbe probe;
  final StremioSubtitleService subtitleService;
  final StreamServerHealthRepository healthRepository;
  final Map<String, PreparedPlayback> _cache = {};
  final Map<String, Future<PreparedPlayback>> _inflight = {};

  PlaybackPreparationService({
    required this.resolver,
    required this.probe,
    required this.subtitleService,
    this.healthRepository = const StreamServerHealthRepository(),
  });

  PreparedPlayback? peek(PlaybackPreparationRequest request) {
    final prepared = _cache[request.cacheKey];
    if (prepared == null) return null;
    if (DateTime.now().difference(prepared.preparedAt) > _ttl) {
      _cache.remove(request.cacheKey);
      return null;
    }
    return prepared;
  }

  Future<PreparedPlayback> prepare(
    PlaybackPreparationRequest request, {
    bool forceRefresh = false,
  }) {
    if (!forceRefresh) {
      final cached = peek(request);
      if (cached != null) return Future.value(cached);
      final pending = _inflight[request.cacheKey];
      if (pending != null) return pending;
    }

    final future = _prepare(request);
    _inflight[request.cacheKey] = future;
    return future.whenComplete(() => _inflight.remove(request.cacheKey));
  }

  Future<PreparedPlayback> _prepare(PlaybackPreparationRequest request) async {
    final candidates = await resolver.resolve(
      mediaType: request.mediaType,
      mediaId: request.mediaId.toString(),
      externalId: request.externalId,
      title: request.title,
      year: request.year,
      season: request.season,
      episode: request.episode,
    );

    final inApp = candidates
        .where((candidate) => candidate.backend != PlaybackBackend.external)
        .toList(growable: false);
    final ranked = _ranker.rank(inApp);
    final probed =
        ranked.isEmpty ? ranked : await probe.preferReachable(ranked);
    final healthy = await healthRepository.rankFor(
      request.playbackContext.historyKey,
      probed,
    );

    var subtitles = const <PlaybackSubtitle>[];
    if (healthy.isNotEmpty) {
      try {
        final found = await subtitleService.forPlayback(request.playbackContext);
        subtitles = [
          for (final subtitle in found.where((value) => value.isSpanish).take(6))
            PlaybackSubtitle(
              uri: subtitle.url,
              language: subtitle.language,
              label: subtitle.label,
            ),
        ];
      } catch (_) {
        // External subtitles are optional; video preparation must still finish.
      }
    }

    final prepared = PreparedPlayback(
      request: request,
      candidates: List.unmodifiable(healthy),
      subtitles: List.unmodifiable(subtitles),
      preparedAt: DateTime.now(),
    );
    _cache[request.cacheKey] = prepared;
    _trim();

    if (healthy.isNotEmpty) {
      unawaited(_preloadBest(
        healthy.first,
        request.title,
        subtitles,
      ));
    }
    return prepared;
  }

  Future<void> _preloadBest(
    StreamCandidate candidate,
    String title,
    List<PlaybackSubtitle> subtitles,
  ) async {
    if (!Platform.isAndroid ||
        candidate.backend != PlaybackBackend.native ||
        candidate.headers.isNotEmpty ||
        !candidate.uri.hasAuthority ||
        (candidate.uri.scheme != 'https' && candidate.uri.scheme != 'http')) {
      return;
    }
    try {
      await _preloadChannel.invokeMethod<void>('preload', {
        'uri': candidate.uri.toString(),
        'title': title,
        'durationMs': 3000,
        'subtitles': [
          for (final subtitle in subtitles)
            {
              'uri': subtitle.uri.toString(),
              'language': subtitle.language,
              'label': subtitle.label,
            },
        ],
      });
    } on PlatformException {
      // Preload is opportunistic; normal playback remains authoritative.
    } on MissingPluginException {
      // Non-Media3 builds still work through the normal player path.
    }
  }

  void _trim() {
    final expired = _cache.entries
        .where((entry) => DateTime.now().difference(entry.value.preparedAt) > _ttl)
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final key in expired) {
      _cache.remove(key);
    }
    if (_cache.length <= _maxEntries) return;
    final ordered = _cache.entries.toList()
      ..sort((a, b) => a.value.preparedAt.compareTo(b.value.preparedAt));
    for (final entry in ordered.take(_cache.length - _maxEntries)) {
      _cache.remove(entry.key);
    }
  }
}
