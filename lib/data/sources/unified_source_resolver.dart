import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/stream_candidate.dart';
import '../../domain/services/source_resolver.dart';
import '../addons/stremio_source_resolver.dart';
import '../anime/anime_id_mapping_service.dart';
import '../anime/anime_official_streaming_resolver.dart';
import 'http_source_resolver.dart';

final unifiedSourceResolverProvider = Provider<UnifiedSourceResolver>((ref) {
  return UnifiedSourceResolver(
    http: ref.read(httpSourceResolverProvider),
    stremio: ref.read(stremioSourceResolverProvider),
    animeMapping: ref.read(animeIdMappingServiceProvider),
    animeOfficial: ref.read(animeOfficialStreamingProvider),
  );
});

class UnifiedSourceResolver implements SourceResolver {
  final HttpSourceResolver http;
  final StremioSourceResolver stremio;
  final AnimeIdMappingService animeMapping;
  final AnimeOfficialStreamingResolver animeOfficial;

  const UnifiedSourceResolver({
    required this.http,
    required this.stremio,
    required this.animeMapping,
    required this.animeOfficial,
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
      _resolveOfficialAnime(
        mediaType: mediaType,
        mediaId: mediaId,
        episode: episode,
      ),
    ]);

    return [
      for (final batch in batches) ...batch,
    ];
  }

  Future<List<StreamCandidate>> _resolveOfficialAnime({
    required String mediaType,
    required String mediaId,
    required int? episode,
  }) async {
    if (mediaType != 'anime' || episode == null) return const [];
    final anilistId = int.tryParse(mediaId);
    if (anilistId == null) return const [];

    return animeOfficial.resolve(
      anilistId: anilistId,
      episode: episode,
    );
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
