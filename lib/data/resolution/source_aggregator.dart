import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/stream_candidate.dart';
import '../../domain/resolution/provider_resolver.dart';
import '../debug/debug_log_provider.dart';
import '../extractors/resolver_manager.dart';
import 'provider_registry.dart';

final sourceAggregatorProvider = Provider<SourceAggregator>((ref) {
  return SourceAggregator(
    ref.read(providerRegistryProvider),
    resolverManager: ref.read(resolverManagerProvider),
  );
});

class SourceAggregator {
  final List<ProviderResolver> providers;
  final Duration providerTimeout;
  final Duration resolutionTimeout;
  final Duration firstCandidateGrace;
  final Duration cacheTtl;
  final Duration negativeCacheTtl;
  final ResolverManager? resolverManager;

  final Map<String, _CachedResolution> _cache = {};
  final Map<String, Future<ProviderResolutionResult>> _inFlight = {};

  SourceAggregator(
    this.providers, {
    this.providerTimeout = const Duration(seconds: 18),
    this.resolutionTimeout = const Duration(seconds: 17),
    this.firstCandidateGrace = const Duration(milliseconds: 900),
    this.cacheTtl = const Duration(minutes: 5),
    this.negativeCacheTtl = const Duration(seconds: 30),
    this.resolverManager,
  });

  Future<ProviderResolutionResult> resolve(
    ProviderResolveRequest request,
  ) {
    final key = _cacheKey(request);
    final cached = _cache[key];
    if (cached != null) {
      final ttl = cached.result.candidates.isEmpty ? negativeCacheTtl : cacheTtl;
      if (DateTime.now().difference(cached.createdAt) <= ttl) {
        final cacheLog =
            'SourceAggregator CACHE ${request.mediaType}:${request.mediaId} -> ${cached.result.candidates.length} fuentes.';
        debugPrint(cacheLog);
        addDebugLog(cacheLog);
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

    final activeAddonsLog =
        'SourceAggregator START ${request.mediaType}:${request.mediaId} '
        'title="${request.title ?? ''}" S${request.season ?? '-'}E${request.episode ?? '-'} '
        '-> ${eligible.length} providers elegibles: '
        '${eligible.map((provider) => provider.displayName).join(', ')}';
    debugPrint(activeAddonsLog);
    addDebugLog(activeAddonsLog);

    if (eligible.isEmpty) {
      const emptyLog = 'SourceAggregator END -> 0 providers, 0 fuentes.';
      debugPrint(emptyLog);
      addDebugLog(emptyLog);
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
      final result = snapshot();
      final finishLog =
          'SourceAggregator END -> ${result.candidates.length} fuentes; '
          'providers elegibles=${result.providersEligible}, '
          'completados=${result.providersCompleted}, fallidos=${result.providersFailed}.';
      debugPrint(finishLog);
      addDebugLog(finishLog);
      completer.complete(result);
    }

    globalTimer = Timer(resolutionTimeout, () {
      final timeoutLog =
          'SourceAggregator TIMEOUT global ${resolutionTimeout.inSeconds}s; '
          'fuentes parciales=${candidates.length}, providers pendientes=$remaining.';
      debugPrint(timeoutLog);
      addDebugLog(timeoutLog);
      finish();
    });

    for (final provider in eligible) {
      unawaited(
        _resolveProvider(provider, request).then((batch) {
          if (completer.isCompleted) return;

          final providerLog =
              'SourceAggregator provider ${provider.displayName} (${provider.id}) -> '
              '${batch.candidates.length} fuentes${batch.failed ? ' · FALLÓ' : ''}.';
          debugPrint(providerLog);
          addDebugLog(providerLog);

          for (var index = 0; index < batch.candidates.length; index++) {
            final candidate = batch.candidates[index];
            final urlLog =
                'SourceAggregator ${provider.id} URL ${index + 1}/${batch.candidates.length} '
                '-> ${candidate.uri}';
            debugPrint(urlLog);
            addDebugLog(urlLog);
          }

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
    final startLog = 'Resolver ${provider.displayName} START (${provider.id}).';
    debugPrint(startLog);
    addDebugLog(startLog);

    late final Future<List<StreamCandidate>> providerFuture;
    try {
      providerFuture = provider.resolve(request);
    } catch (error, stackTrace) {
      final errorLog =
          'Resolver ${provider.displayName} ERROR ${error.runtimeType}: $error';
      final stackLog = 'Resolver ${provider.displayName} STACK: $stackTrace';
      debugPrint(errorLog);
      debugPrint(stackLog);
      addDebugLog(errorLog);
      addDebugLog(stackLog);
      return Future.value(
        const _ProviderBatch(candidates: [], failed: true),
      );
    }

    final normalized = providerFuture.then<_ProviderBatch>(
      (candidates) => _ProviderBatch(candidates: candidates),
      onError: (Object error, StackTrace stackTrace) {
        final errorLog =
            'Resolver ${provider.displayName} ERROR ${error.runtimeType}: $error';
        final stackLog = 'Resolver ${provider.displayName} STACK: $stackTrace';
        debugPrint(errorLog);
        debugPrint(stackLog);
        addDebugLog(errorLog);
        addDebugLog(stackLog);
        return const _ProviderBatch(candidates: [], failed: true);
      },
    );

    final postProcessed = normalized.then((batch) async {
      final manager = resolverManager;
      if (manager == null || batch.failed || batch.candidates.isEmpty) {
        return batch;
      }

      try {
        final resolved = await manager.resolveCandidates(batch.candidates);
        return _ProviderBatch(candidates: resolved);
      } catch (_) {
        return batch;
      }
    });

    return postProcessed.timeout(
      providerTimeout,
      onTimeout: () {
        final timeoutLog =
            'Resolver ${provider.displayName} TIMEOUT después de '
            '${providerTimeout.inSeconds}s.';
        debugPrint(timeoutLog);
        addDebugLog(timeoutLog);
        return const _ProviderBatch(candidates: [], failed: true);
      },
    );
  }

  String _cacheKey(ProviderResolveRequest request) {
    return [
      request.mediaType,
      request.mediaId,
      request.externalId ?? '',
      request.season?.toString() ?? '',
      request.episode?.toString() ?? '',
      request.embedUrl ?? '',
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
