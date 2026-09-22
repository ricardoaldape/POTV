import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/stream_candidate.dart';
import '../../domain/resolution/provider_resolver.dart';
import 'provider_registry.dart';

final sourceAggregatorProvider = Provider<SourceAggregator>((ref) {
  return SourceAggregator(ref.read(providerRegistryProvider));
});

class SourceAggregator {
  final List<ProviderResolver> providers;
  final Duration providerTimeout;
  final Duration resolutionTimeout;
  final Duration firstCandidateGrace;
  final Duration cacheTtl;
  final Duration negativeCacheTtl;

  final Map<String, _CachedResolution> _cache = {};
  final Map<String, Future<ProviderResolutionResult>> _inFlight = {};

  SourceAggregator(
    this.providers, {
    this.providerTimeout = const Duration(seconds: 12),
    this.resolutionTimeout = const Duration(seconds: 9),
    this.firstCandidateGrace = const Duration(milliseconds: 900),
    this.cacheTtl = const Duration(minutes: 5),
    this.negativeCacheTtl = const Duration(seconds: 30),
  });

  Future<ProviderResolutionResult> resolve(
    ProviderResolveRequest request,
  ) {
    final key = _cacheKey(request);
    final cached = _cache[key];
    if (cached != null) {
      final ttl = cached.result.candidates.isEmpty ? negativeCacheTtl : cacheTtl;
      if (DateTime.now().difference(cached.createdAt) <= ttl) {
        return Future.value(cached.result);
      }
      _cache.remove(key);
    }

    final running = _inFlight[key];
    if (running != null) return running;

    final future = _resolveFresh(request);
    _inFlight[key] = future;
    return future.then((result) {
      _cache[key] = _CachedResolution(
        result: result,
        createdAt: DateTime.now(),
      );
      return result;
    }).whenComplete(() {
      _inFlight.remove(key);
    });
  }

  void clearCache() {
    _cache.clear();
  }

  Future<ProviderResolutionResult> _resolveFresh(
    ProviderResolveRequest request,
  ) {
    final eligible = providers
        .where((provider) => provider.supports(request))
        .toList(growable: false);

    if (eligible.isEmpty) {
      return Future.value(
        const ProviderResolutionResult(
          candidates: [],
          providersEligible: 0,
          providersCompleted: 0,
          providersFailed: 0,
        ),
      );
    }

    final completer = Completer<ProviderResolutionResult>();
    final candidates = <StreamCandidate>[];
    var completed = 0;
    var failed = 0;
    var remaining = eligible.length;
    Timer? graceTimer;
    late final Timer globalTimer;

    ProviderResolutionResult snapshot() {
      return ProviderResolutionResult(
        candidates: List<StreamCandidate>.unmodifiable(candidates),
        providersEligible: eligible.length,
        providersCompleted: completed,
        providersFailed: failed,
      );
    }

    void finish() {
      if (completer.isCompleted) return;
      graceTimer?.cancel();
      globalTimer.cancel();
      completer.complete(snapshot());
    }

    globalTimer = Timer(resolutionTimeout, finish);

    for (final provider in eligible) {
      unawaited(
        _resolveProvider(provider, request).then((batch) {
          if (completer.isCompleted) return;

          remaining--;
          if (batch.failed) {
            failed++;
          } else {
            completed++;
            if (batch.candidates.isNotEmpty) {
              final firstCandidate = candidates.isEmpty;
              candidates.addAll(batch.candidates);
              if (firstCandidate && firstCandidateGrace > Duration.zero) {
                graceTimer = Timer(firstCandidateGrace, finish);
              }
            }
          }

          if (remaining == 0) {
            finish();
          } else if (candidates.isNotEmpty &&
              firstCandidateGrace <= Duration.zero) {
            finish();
          }
        }),
      );
    }

    return completer.future;
  }

  Future<_ProviderBatch> _resolveProvider(
    ProviderResolver provider,
    ProviderResolveRequest request,
  ) {
    late final Future<List<StreamCandidate>> providerFuture;
    try {
      providerFuture = provider.resolve(request);
    } catch (_) {
      return Future.value(
        const _ProviderBatch(candidates: [], failed: true),
      );
    }

    final normalized = providerFuture.then<_ProviderBatch>(
      (candidates) => _ProviderBatch(candidates: candidates),
      onError: (Object _, StackTrace _) =>
          const _ProviderBatch(candidates: [], failed: true),
    );

    return normalized.timeout(
      providerTimeout,
      onTimeout: () => const _ProviderBatch(candidates: [], failed: true),
    );
  }

  String _cacheKey(ProviderResolveRequest request) {
    return [
      request.mediaType,
      request.mediaId,
      request.externalId ?? '',
      request.season?.toString() ?? '',
      request.episode?.toString() ?? '',
    ].join('|');
  }
}

class _CachedResolution {
  final ProviderResolutionResult result;
  final DateTime createdAt;

  const _CachedResolution({
    required this.result,
    required this.createdAt,
  });
}

class _ProviderBatch {
  final List<StreamCandidate> candidates;
  final bool failed;

  const _ProviderBatch({
    required this.candidates,
    this.failed = false,
  });
}
