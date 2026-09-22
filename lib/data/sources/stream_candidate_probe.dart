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
  }) async {
    if (ranked.length <= 1) return ranked;

    final toProbe = ranked.take(maxProbe).toList(growable: false);
    final results = await Future.wait([
      for (final candidate in toProbe) _check(candidate),
    ]);

    final healthy = <StreamCandidate>[];
    final unknown = <StreamCandidate>[];

    for (var i = 0; i < toProbe.length; i++) {
      switch (results[i]) {
        case _ProbeResult.healthy:
          healthy.add(toProbe[i]);
          break;
        case _ProbeResult.unknown:
          unknown.add(toProbe[i]);
          break;
        case _ProbeResult.dead:
          break;
      }
    }

    final remaining = ranked.skip(toProbe.length).toList(growable: false);

    if (healthy.isEmpty) {
      // A probe can be blocked while the native player is still accepted.
      // Keep the original order instead of turning a false negative into
      // "no source".
      return ranked;
    }

    return [
      ...healthy,
      ...unknown,
      ...remaining,
    ];
  }

  Future<_ProbeResult> _check(StreamCandidate candidate) async {
    if (candidate.backend != PlaybackBackend.native) {
      return _ProbeResult.unknown;
    }

    final uri = candidate.uri;
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return _ProbeResult.unknown;
    }

    if (!_looksLikeHls(uri)) return _ProbeResult.unknown;

    try {
      final response = await _dio.getUri<String>(
        uri,
        options: Options(
          responseType: ResponseType.plain,
          headers: {
            ...candidate.headers,
            'Accept': 'application/vnd.apple.mpegurl,application/x-mpegURL,*/*',
          },
        ),
      );

      final body = response.data?.trimLeft() ?? '';
      if (body.startsWith('#EXTM3U')) return _ProbeResult.healthy;
      return _ProbeResult.dead;
    } on DioException {
      return _ProbeResult.dead;
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
