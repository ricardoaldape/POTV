import '../../domain/models/stream_candidate.dart';
import '../../domain/resolution/provider_resolver.dart';
import '../addons/stremio_source_resolver.dart';
import '../anime/anime_id_mapping_service.dart';
import '../sources/http_source_resolver.dart';
import '../sources/public_domain_movie_resolver.dart';
import '../sources/public_domain_series_resolver.dart';

class HttpProviderResolver extends ProviderResolver {
  final HttpSourceResolver resolver;

  const HttpProviderResolver(this.resolver);

  @override
  String get id => 'http';

  @override
  String get displayName => 'HTTP Providers';

  @override
  int get priority => 20;

  @override
  Set<String> get supportedMediaTypes => const {'movie', 'tv', 'anime'};

  @override
  Future<List<StreamCandidate>> resolve(ProviderResolveRequest request) {
    return resolver.resolve(
      mediaType: request.mediaType,
      mediaId: request.mediaId,
      externalId: request.externalId,
      title: request.title,
      year: request.year,
      season: request.season,
      episode: request.episode,
    );
  }
}
class StremioProviderResolver extends ProviderResolver {
  final StremioSourceResolver resolver;
  final AnimeIdMappingService animeMapping;

  const StremioProviderResolver({
    required this.resolver,
    required this.animeMapping,
  });

  @override
  String get id => 'addons';

  @override
  String get displayName => 'Addons compatibles';

  @override
  int get priority => 10;

  @override
  Set<String> get supportedMediaTypes => const {'movie', 'tv', 'anime'};

  @override
  Future<List<StreamCandidate>> resolve(ProviderResolveRequest request) async {
    if (!request.isAnime) {
      return resolver.resolve(
        mediaType: request.mediaType,
        mediaId: request.mediaId,
        externalId: request.externalId,
        title: request.title,
        year: request.year,
        season: request.season,
        episode: request.episode,
      );
    }

    final anilistId = int.tryParse(request.mediaId);
    final absoluteEpisode = request.episode;
    if (anilistId == null || absoluteEpisode == null) return const [];

    final mapped = await animeMapping.mapEpisode(
      anilistId: anilistId,
      absoluteEpisode: absoluteEpisode,
      title: request.title,
    );
    if (mapped == null || !mapped.canUseSeriesProtocol) return const [];

    return resolver.resolve(
      mediaType: 'tv',
      mediaId: request.mediaId,
      externalId: mapped.imdbId,
      title: request.title,
      year: request.year,
      season: mapped.season,
      episode: mapped.episode,
    );
  }
}
class PublicDomainMovieProviderResolver extends ProviderResolver {
  final PublicDomainMovieResolver resolver;

  const PublicDomainMovieProviderResolver(this.resolver);

  @override
  String get id => 'archive-movie';

  @override
  String get displayName => 'Internet Archive · Películas';

  @override
  int get priority => 80;

  @override
  Set<String> get supportedMediaTypes => const {'movie'};

  @override
  Future<List<StreamCandidate>> resolve(ProviderResolveRequest request) {
    return resolver.resolve(
      mediaType: request.mediaType,
      title: request.title,
      year: request.year,
    );
  }
}

class PublicDomainSeriesProviderResolver extends ProviderResolver {
  final PublicDomainSeriesResolver resolver;

  const PublicDomainSeriesProviderResolver(this.resolver);

  @override
  String get id => 'archive-series';

  @override
  String get displayName => 'Internet Archive · Series';

  @override
  int get priority => 80;

  @override
  Set<String> get supportedMediaTypes => const {'tv'};

  @override
  Future<List<StreamCandidate>> resolve(ProviderResolveRequest request) {
    return resolver.resolve(
      mediaType: request.mediaType,
      title: request.title,
      season: request.season,
      episode: request.episode,
    );
  }
}
