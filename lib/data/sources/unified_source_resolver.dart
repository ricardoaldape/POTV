import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/stream_candidate.dart';
import '../../domain/services/source_resolver.dart';
import '../addons/stremio_source_resolver.dart';
import 'http_source_resolver.dart';

final unifiedSourceResolverProvider = Provider<UnifiedSourceResolver>((ref) {
  return UnifiedSourceResolver(
    http: ref.read(httpSourceResolverProvider),
    stremio: ref.read(stremioSourceResolverProvider),
  );
});

class UnifiedSourceResolver implements SourceResolver {
  final HttpSourceResolver http;
  final StremioSourceResolver stremio;

  const UnifiedSourceResolver({
    required this.http,
    required this.stremio,
  });

  @override
  Future<List<StreamCandidate>> resolve({
    required String mediaType,
    required String mediaId,
    String? externalId,
    String? title,
    int? season,
    int? episode,
  }) async {
    final batches = await Future.wait([
      http.resolve(
        mediaType: mediaType,
        mediaId: mediaId,
        externalId: externalId,
        title: title,
        season: season,
        episode: episode,
      ),
      stremio.resolve(
        mediaType: mediaType,
        mediaId: mediaId,
        externalId: externalId,
        title: title,
        season: season,
        episode: episode,
      ),
    ]);

    return [
      for (final batch in batches) ...batch,
    ];
  }
}
