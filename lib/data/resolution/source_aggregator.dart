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
  final Duration cacheTtl;

  final Map<String, _CachedResolution> _cache = {};
  final Map<String, Future<ProviderResolutionResult>> _inFlight = {};

  SourceAggregator(
    this.providers, {
    this.providerTimeout = const Duration(seconds: 18),
    this.cacheTtl = const Duration(minutes: 5),
  });

  Future<ProviderResolutionResult> resolve(
    ProviderResolveRequest request,
  ) {
    final key = _cacheKey(request);
    final cached = _cache[key];
    if (cached != null &&
        DateTime.now().difference(cached.createdAt) <= cacheTtl) {
      return Future.value(cached.result);
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
  ) async {
    final eligible = providers
        .where((provider) => provider.supports(request))
        .toList(growable: false);

    final batches = await Future.wait([
      for (final provider in eligible) _resolveProvider(provider, request),
    ]);

    final candidates = <StreamCandidate>[];
    var completed = 0;
    var failed = 0;

    for (final batch in batches) {
      if (batch.failed) {
        failed++;
        continue;
      }
      completed++;
      candidates.addAll(batch.candidates);
    }

    return ProviderResolutionResult(
      candidates: candidates,
      providersEligible: eligible.length,
      providersCompleted: completed,
      providersFailed: failed,
    );
  }

  Future<_ProviderBatch> _resolveProvider(
    ProviderResolver provider,
    ProviderResolveRequest request,
  ) async {
    try {
      final candidates = await provider
          .resolve(request)
          .timeout(providerTimeout, onTimeout: () => const []);
      return _ProviderBatch(candidates: candidates);
    } catch (_) {
      return const _ProviderBatch(
        candidates: [],
        failed: true,
      );
    }
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
