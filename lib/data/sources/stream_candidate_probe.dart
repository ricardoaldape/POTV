import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/stream_candidate.dart';

final streamCandidateProbeProvider = Provider<StreamCandidateProbe>((ref) {
  return StreamCandidateProbe(
    Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 4),
        receiveTimeout: const Duration(seconds: 5),
        validateStatus: (status) =>
            status != null && status >= 200 && status < 400,
      ),
    ),
  );
});

class StreamCandidateProbe {
  final Dio _dio;

  StreamCandidateProbe(this._dio);

  Future<List<StreamCandidate>> preferReachable(
    List<StreamCandidate> ranked, {
    int maxProbe = 6,
    bool dropDeadWhenCertain = false,
  }) async {
    if (ranked.isEmpty) return ranked;

    final toProbe = ranked.take(maxProbe).toList(growable: false);
    final results = await Future.wait([
      for (final candidate in toProbe) _check(candidate),
    ]);

    final healthy = <StreamCandidate>[];
    final unknown = <StreamCandidate>[];

    for (var i = 0; i < toProbe.length; i++) {
      final assessed = results[i];
      switch (assessed.status) {
        case _ProbeResult.healthy:
          healthy.add(assessed.candidate);
          break;
        case _ProbeResult.unknown:
          unknown.add(assessed.candidate);
          break;
        case _ProbeResult.dead:
          break;
      }
    }

    final remaining = ranked.skip(toProbe.length).toList(growable: false);

    if (healthy.isEmpty) {
      if (dropDeadWhenCertain && unknown.isEmpty && remaining.isEmpty) {
        return const [];
      }
      // A probe can be blocked while the native player is still accepted.
      // Keep the original order instead of turning a false negative into
      // "no source" unless every probed candidate is conclusively dead.
      return ranked;
    }

    return [...healthy, ...unknown, ...remaining];
  }

  // A URL without .m3u8/.mp4 is not necessarily an embed. Many legitimate
  // partner CDNs serve signed media behind extensionless paths.
  Future<_ProbeAssessment> _check(StreamCandidate candidate) async {
    // The authorized POTV VOD gateway already returned this stream for the
    // active subscriber. Signed CDN URLs may reject HEAD even when Media3
    // can play GET; do not probe, consume, or discard those capabilities.
    // Leave actual playback/failover as the authoritative health check.
    if (candidate.id.startsWith('potv_partner_api:')) {
      return _ProbeAssessment(_ProbeResult.unknown, candidate);
    }

    if (candidate.uri.scheme != 'http' && candidate.uri.scheme != 'https') {
      return _ProbeAssessment(_ProbeResult.unknown, candidate);
    }

    if (candidate.backend == PlaybackBackend.webView) {
      // HEAD never downloads a movie. A failed/disallowed HEAD is inconclusive:
      // do not turn an embed into a dead stream.
      try {
        final response = await _dio.headUri<Object?>(
          candidate.uri,
          options: Options(headers: candidate.headers),
        );
        final contentType =
            response.headers.value(Headers.contentTypeHeader)?.toLowerCase() ??
            '';
        final isDirect =
            contentType.startsWith('video/') ||
            contentType.contains('mpegurl') ||
            contentType.contains('dash+xml');
        if (isDirect) {
          return _ProbeAssessment(
            _ProbeResult.healthy,
            StreamCandidate(
              id: candidate.id,
              label: candidate.label,
              uri: candidate.uri,
              language: candidate.language,
              quality: candidate.quality,
              backend: PlaybackBackend.native,
              headers: candidate.headers,
              externalAudioUri: candidate.externalAudioUri,
              allowedHosts: candidate.allowedHosts,
              directWebView: candidate.directWebView,
            ),
          );
        }
      } on DioException {
        // HEAD can fail on perfectly valid signed URLs. Keep the embed.
      }
      return _ProbeAssessment(_ProbeResult.unknown, candidate);
    }

    if (candidate.backend != PlaybackBackend.native) {
      return _ProbeAssessment(_ProbeResult.unknown, candidate);
    }

    if (!_looksLikeHls(candidate.uri)) {
      try {
        final response = await _dio.headUri<Object?>(
          candidate.uri,
          options: Options(headers: candidate.headers),
        );
        final type =
            response.headers.value(Headers.contentTypeHeader)?.toLowerCase() ??
            '';
        final looksMedia =
            type.startsWith('video/') ||
            type.startsWith('audio/') ||
            type.contains('mpegurl') ||
            type.contains('octet-stream') ||
            type.contains('mp2t');
        return _ProbeAssessment(
          looksMedia ? _ProbeResult.healthy : _ProbeResult.unknown,
          candidate,
        );
      } on DioException catch (error) {
        final status = error.response?.statusCode;
        if (status == 401 || status == 403 || status == 404 || status == 410) {
          return _ProbeAssessment(_ProbeResult.dead, candidate);
        }
        return _ProbeAssessment(_ProbeResult.unknown, candidate);
      }
    }

    try {
      final response = await _dio.getUri<String>(
        candidate.uri,
        options: Options(
          responseType: ResponseType.plain,
          headers: {
            ...candidate.headers,
            'Accept': 'application/vnd.apple.mpegurl,application/x-mpegURL,*/*',
          },
        ),
      );

      final body = response.data?.trimLeft() ?? '';
      return _ProbeAssessment(
        body.startsWith('#EXTM3U') ? _ProbeResult.healthy : _ProbeResult.dead,
        candidate,
      );
    } on DioException catch (error) {
      // A timeout, temporary CDN failure or rejected probe is not proof
      // that Media3 cannot play the stream. Only a missing/gone resource
      // is conclusively unavailable here.
      final status = error.response?.statusCode;
      return _ProbeAssessment(
        status == 404 || status == 410
            ? _ProbeResult.dead
            : _ProbeResult.unknown,
        candidate,
      );
    }
  }

  bool _looksLikeHls(Uri uri) {
    final path = uri.path.toLowerCase();
    if (path.endsWith('.m3u8') ||
        path.contains('.m3u8/') ||
        path.contains('manifest')) {
      return true;
    }

    for (final value in uri.queryParameters.values) {
      if (value.toLowerCase().contains('.m3u8')) return true;
    }
    return false;
  }
}

enum _ProbeResult { healthy, dead, unknown }

class _ProbeAssessment {
  final _ProbeResult status;
  final StreamCandidate candidate;

  const _ProbeAssessment(this.status, this.candidate);
}
