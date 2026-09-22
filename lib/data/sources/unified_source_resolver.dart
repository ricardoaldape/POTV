import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/stream_candidate.dart';
import '../../domain/services/source_resolver.dart';
import '../addons/stremio_source_resolver.dart';
import '../anime/anime_id_mapping_service.dart';
import 'http_source_resolver.dart';

final unifiedSourceResolverProvider = Provider<UnifiedSourceResolver>((ref) {
  return UnifiedSourceResolver(
    http: ref.read(httpSourceResolverProvider),
    stremio: ref.read(stremioSourceResolverProvider),
    animeMapping: ref.read(animeIdMappingServiceProvider),
  );
});

class UnifiedSourceResolver implements SourceResolver {
  final HttpSourceResolver http;
  final StremioSourceResolver stremio;
  final AnimeIdMappingService animeMapping;

  const UnifiedSourceResolver({
    required this.http,
    required this.stremio,
    required this.animeMapping,
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
      _resolveStremio(
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

  Future<List<StreamCandidate>> _resolveStremio({
    required String mediaType,
    required String mediaId,
    String? externalId,
    String? title,
    int? season,
    int? episode,
  }) async {
    if (mediaType != 'anime') {
      return stremio.resolve(
        mediaType: mediaType,
        mediaId: mediaId,
        externalId: externalId,
        title: title,
        season: season,
        episode: episode,
      );
    }

    final anilistId = int.tryParse(mediaId);
    if (anilistId == null || episode == null) return const [];

    final mapped = await animeMapping.mapEpisode(
      anilistId: anilistId,
      absoluteEpisode: episode,
    );
    if (mapped == null || !mapped.canUseSeriesProtocol) return const [];

    return stremio.resolve(
      mediaType: 'tv',
      mediaId: mediaId,
      externalId: mapped.imdbId,
      title: title,
      season: mapped.season,
      episode: mapped.episode,
    );
  }
}
