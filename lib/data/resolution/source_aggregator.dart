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

  const SourceAggregator(
    this.providers, {
    this.providerTimeout = const Duration(seconds: 18),
  });

  Future<ProviderResolutionResult> resolve(
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
}

class _ProviderBatch {
  final List<StreamCandidate> candidates;
  final bool failed;

  const _ProviderBatch({
    required this.candidates,
    this.failed = false,
  });
}
