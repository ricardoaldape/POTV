import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/stream_candidate.dart';
import '../../domain/resolution/provider_resolver.dart';
import '../../domain/services/source_resolver.dart';
import '../resolution/source_aggregator.dart';

final unifiedSourceResolverProvider = Provider<UnifiedSourceResolver>((ref) {
  return UnifiedSourceResolver(ref.read(sourceAggregatorProvider));
});

class UnifiedSourceResolver implements SourceResolver {
  final SourceAggregator aggregator;

  const UnifiedSourceResolver(this.aggregator);

  @override
  Future<List<StreamCandidate>> resolve({
    required String mediaType,
    required String mediaId,
    String? externalId,
    String? title,
    String? year,
    int? season,
    int? episode,
  }) async {
    final result = await aggregator.resolve(
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

    return result.candidates;
  }
}
