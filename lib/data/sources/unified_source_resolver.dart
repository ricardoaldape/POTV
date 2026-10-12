import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/stream_candidate.dart';
import '../../domain/resolution/provider_resolver.dart';
import '../../domain/services/source_resolver.dart';
import '../resolution/source_aggregator.dart';

final unifiedSourceResolverProvider = Provider<UnifiedSourceResolver>((ref) {
  return UnifiedSourceResolver(ref.read(sourceAggregatorProvider));
});

/// Coalesces detail-screen warm-up and Play actions for the *same* item.
///
/// The cache is process-memory only: never persisted or shared across accounts.
/// Signed URLs can expire, therefore hits have a deliberately short lifetime.
/// Call invalidate() whenever provider configuration or credentials change.
class UnifiedSourceResolver implements SourceResolver {
  final SourceAggregator aggregator;
  UnifiedSourceResolver(this.aggregator);

  static const _ttl = Duration(seconds: 20);
  static const _maxEntries = 12;
  final Map<String, _ResolvedCacheEntry> _cache = {};
  final Map<String, Future<List<StreamCandidate>>> _pending = {};

  void invalidate() {
    _cache.clear();
    _pending.clear();
  }

  @override
  Future<List<StreamCandidate>> resolve({
    required String mediaType,
    required String mediaId,
    String? externalId,
    String? title,
    String? year,
    int? season,
    int? episode,
  }) {
    final key = jsonEncode([
      mediaType, mediaId, externalId, title, year, season, episode,
    ]);
    final now = DateTime.now();
    _cache.removeWhere((_, value) => !value.expiresAt.isAfter(now));
    final hit = _cache[key];
    if (hit != null) return Future.value(hit.candidates);
    final inFlight = _pending[key];
    if (inFlight != null) return inFlight;

    final pending = _resolveAndCache(
      key,
      ProviderResolveRequest(
        mediaType: mediaType,
        mediaId: mediaId,
        externalId: externalId,
        title: title,
        year: year,
        season: season,
        episode: episode,
      ),
    );
    _pending[key] = pending;
    return pending;
  }

  Future<List<StreamCandidate>> _resolveAndCache(
    String key,
    ProviderResolveRequest request,
  ) async {
    try {
      final response = await aggregator.resolve(request);
      final candidates = List<StreamCandidate>.unmodifiable(response.candidates);
      // Never retain unsuccessful lookup results, allowing quick retry.
      if (candidates.isNotEmpty && _pending.containsKey(key)) {
        if (_cache.length >= _maxEntries) _cache.remove(_cache.keys.first);
        _cache[key] = _ResolvedCacheEntry(
          candidates,
          DateTime.now().add(_ttl),
        );
      }
      return candidates;
    } finally {
      _pending.remove(key);
    }
  }
}

class _ResolvedCacheEntry {
  final List<StreamCandidate> candidates;
  final DateTime expiresAt;

  const _ResolvedCacheEntry(this.candidates, this.expiresAt);
}
