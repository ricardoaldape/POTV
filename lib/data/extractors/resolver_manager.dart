import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/extractors_config.dart';
import '../../domain/models/stream_candidate.dart';
import 'generic_extractor.dart';

final resolverManagerProvider = Provider<ResolverManager>((ref) {
  return ResolverManager();
});

class ResolverManager {
  final List<_RegisteredExtractor> _extractors;

  ResolverManager({
    List<ExtractorConfig>? configs,
  }) : _extractors = [
          for (final config in configs ?? ExtractorsConfig.configs)
            _RegisteredExtractor(
              config: config,
              extractor: GenericExtractor(config),
            ),
        ];

  Future<List<StreamCandidate>> resolveCandidates(
    Iterable<StreamCandidate> candidates,
  ) async {
    if (_extractors.isEmpty) return List<StreamCandidate>.of(candidates);

    final batches = await Future.wait([
      for (final candidate in candidates) resolveCandidate(candidate),
    ]);

    final result = <StreamCandidate>[];
    final seen = <String>{};
    for (final batch in batches) {
      for (final candidate in batch) {
        final key = [
          candidate.backend.name,
          candidate.uri.toString(),
          candidate.language ?? '',
        ].join('|');
        if (seen.add(key)) result.add(candidate);
      }
    }
    return result;
  }

  Future<List<StreamCandidate>> resolveCandidate(
    StreamCandidate candidate,
  ) async {
    final matching = _extractors
        .where((entry) => entry.config.matches(candidate.uri))
        .toList(growable: false);
    if (matching.isEmpty) return [candidate];

    final resolved = <StreamCandidate>[];
    for (final entry in matching) {
      try {
        final extracted = await entry.extractor.extract(
          candidate.uri.toString(),
        );
        resolved.addAll([
          for (final stream in extracted) _inherit(candidate, stream),
        ]);
      } catch (_) {
        continue;
      }
    }

    return resolved.isEmpty ? [candidate] : resolved;
  }

  StreamCandidate _inherit(
    StreamCandidate source,
    StreamCandidate extracted,
  ) {
    return StreamCandidate(
      id: '${source.id}:resolved:${extracted.id}',
      label: '${source.label} · ${extracted.label}',
      uri: extracted.uri,
      language: extracted.language ?? source.language,
      quality: extracted.quality ?? source.quality,
      backend: extracted.backend,
      headers: {
        ...source.headers,
        ...extracted.headers,
      },
      externalAudioUri: extracted.externalAudioUri ?? source.externalAudioUri,
      allowedHosts: {
        ...source.allowedHosts,
        ...extracted.allowedHosts,
      },
      directWebView: extracted.directWebView,
    );
  }
}

class _RegisteredExtractor {
  final ExtractorConfig config;
  final GenericExtractor extractor;

  const _RegisteredExtractor({
    required this.config,
    required this.extractor,
  });
}
