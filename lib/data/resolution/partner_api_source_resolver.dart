import 'package:dio/dio.dart';

import '../../domain/models/stream_candidate.dart';
import '../../domain/resolution/provider_resolver.dart';
import '../../domain/resolution/resolver_endpoint_config.dart';
import '../anime/anime_id_mapping_service.dart';
import '../debug/debug_log_provider.dart';
import 'configured_resolver_provider.dart';

/// Optional adapter for a formally authorized provider backend.
/// Understands the VOD route families identified during APK compatibility
/// review, without importing partner login, branding, DRM or payment logic.
/// Auth can only be provided through an explicitly approved account/session.
class PartnerApiSourceResolver extends ProviderResolver {
  final Uri baseUrl;
  final Dio dio;
  final AnimeIdMappingService? animeMapping;
  final Future<Map<String, String>> Function()? sessionHeaders;

  PartnerApiSourceResolver({
    required this.baseUrl,
    Dio? dio,
    this.animeMapping,
    this.sessionHeaders,
  }) : dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 7),
              receiveTimeout: const Duration(seconds: 10),
            ));

  bool get configured =>
      baseUrl.scheme == 'https' &&
      baseUrl.host.isNotEmpty &&
      baseUrl.userInfo.isEmpty &&
      !baseUrl.hasQuery &&
      !baseUrl.hasFragment;

  @override
  String get id => 'potv_partner_api';

  @override
  String get displayName => 'POTV';

  @override
  int get priority => 0;

  @override
  Set<String> get supportedMediaTypes => const {'movie', 'tv', 'anime'};

  @override
  bool supports(ProviderResolveRequest request) =>
      configured && super.supports(request);

  @override
  Future<List<StreamCandidate>> resolve(ProviderResolveRequest request) async {
    if (!supports(request)) return const [];
    var tmdbId = int.tryParse(request.mediaId);
    var season = request.season ?? 1;
    var episode = request.episode ?? 1;
    if (request.isAnime) {
      final anilistId = int.tryParse(request.mediaId);
      if (anilistId == null || animeMapping == null) return const [];
      final mapping = await animeMapping!.mapEpisode(
        anilistId: anilistId,
        absoluteEpisode: episode,
        title: request.title,
      );
      tmdbId = mapping?.tmdbId;
      season = mapping?.season ?? season;
      episode = mapping?.episode ?? episode;
    }
    if (tmdbId == null || tmdbId <= 0) return const [];

    final segments = request.isMovie
        ? [
            'vod/sources/movie/$tmdbId',
            'sources/movie/$tmdbId',
          ]
        : [
            'vod/sources/tv/$tmdbId/$season/$episode',
            if (request.isAnime)
              'sources/anime/$tmdbId/$season/$episode'
            else
              'sources/tv/$tmdbId/$season/$episode',
          ];
    final parser = ConfiguredResolverProvider(ResolverEndpointConfig(
      id: id,
      name: displayName,
      endpoint: baseUrl,
      mediaTypes: supportedMediaTypes,
      priority: priority,
    ));
    Map<String, String> headers;
    try {
      headers = await sessionHeaders?.call() ?? const {};
    } catch (_) {
      // Authorization must come from a user session; never attempt fallback
      // to credentials embedded in another application's binary.
      return const [];
    }

    for (final route in segments) {
      final root = baseUrl.replace(
        path: baseUrl.path.endsWith('/') ? baseUrl.path : '${baseUrl.path}/',
      );
      final endpoint = root.resolve(route);
      if (endpoint.host != baseUrl.host || endpoint.scheme != 'https') {
        continue;
      }
      final query = <String, String>{
        if (request.title != null) 'title': request.title!,
        if (request.year != null && int.tryParse(request.year!) != null)
          'year': request.year!,
        if (request.externalId != null) 'imdb_id': request.externalId!,
        'language': 'es-MX',
        if (request.isAnime) 'is_anime': 'true',
      };
      try {
        final response = await dio.getUri<Object?>(
          endpoint.replace(queryParameters: query),
          options: Options(
            responseType: ResponseType.json,
            // POTV customer bearer tokens must NEVER be forwarded to a
            // redirected origin. All authorized content URLs are resolved
            // separately by the signed POTV gateway.
            followRedirects: false,
            maxRedirects: 0,
            headers: {
              'Accept': 'application/json',
              ...headers,
            },
          ),
        );
        final candidates = parser.parseResponse(response.data);
        if (candidates.isNotEmpty) return candidates;
      } on DioException catch (error) {
        // An explicit 401/403 is an entitlement decision, not an invitation
        // to skip auth or try unrelated private endpoints.
        if (error.response?.statusCode == 401 ||
            error.response?.statusCode == 403) {
          addDebugLog('POTV: sesión del proveedor no autorizada');
          return const [];
        }
        // Only the known legacy route may be tried after an unavailable VOD
        // source. No private API discovery, token scraping or bypass.
      }
    }
    return const [];
  }
}
