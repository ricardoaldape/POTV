import '../../domain/models/stream_candidate.dart';
import '../../domain/resolution/provider_resolver.dart';
import '../extractors/native_resolvers.dart';
import '../extractors/cuevana_extractor.dart';
import '../extractors/tioplus_extractor.dart';
import '../extractors/pelisplus_extractor.dart';
import '../extractors/cinecalidad_extractor.dart';

/// Base adapter that wraps a LolPlus-style extractor stream and converts
/// results into `StreamCandidate`s using `NativeResolvers` when possible.
abstract class _LolPlusAdapterBase extends ProviderResolver {
  const _LolPlusAdapterBase();

  Stream<Map<String, dynamic>> scrape({
    required int tmdbId,
    required bool isMovie,
    required int season,
    required int episode,
  });

  @override
  Future<List<StreamCandidate>> resolve(ProviderResolveRequest request) async {
    final tmdbId = int.tryParse(request.mediaId);
    if (tmdbId == null || tmdbId <= 0) return const [];

    final isMovie = request.mediaType == 'movie';
    final season = request.season ?? 1;
    final episode = request.episode ?? 1;

    final stream = scrape(
      tmdbId: tmdbId,
      isMovie: isMovie,
      season: season,
      episode: episode,
    );

    final candidates = <StreamCandidate>[];

    await for (final Map<String, dynamic> m in stream) {
      final servidorUrl = m['servidor_url']?.toString() ?? '';
      if (servidorUrl.isEmpty) continue;

      final servidorNombre = m['servidor_nombre']?.toString() ??
          m['servidor']?.toString() ??
          'Servidor';
      final calidad = m['calidad']?.toString();
      final idioma = m['idioma']?.toString();

      try {
        final resolved = await NativeResolvers.resolve(
          servidorUrl,
          timeout: const Duration(seconds: 8),
        );

        if (resolved != null && resolved.url.isNotEmpty) {
          candidates.add(StreamCandidate(
            id: '${id}_${candidates.length}',
            label: servidorNombre,
            uri: Uri.parse(resolved.url),
            language: idioma,
            quality: (resolved.quality.isNotEmpty ? resolved.quality : calidad),
            backend: PlaybackBackend.native,
            headers: resolved.headers,
          ));
        } else {
          candidates.add(StreamCandidate(
            id: '${id}_${candidates.length}',
            label: servidorNombre,
            uri: Uri.parse(servidorUrl),
            language: idioma,
            quality: calidad,
            backend: PlaybackBackend.webView,
            directWebView: true,
          ));
        }
      } catch (_) {
        // On error, fallback to webView entry
        try {
          candidates.add(StreamCandidate(
            id: '${id}_${candidates.length}',
            label: servidorNombre,
            uri: Uri.parse(servidorUrl),
            language: idioma,
            quality: calidad,
            backend: PlaybackBackend.webView,
            directWebView: true,
          ));
        } catch (_) {}
      }
    }

    return candidates;
  }
}

class CuevanaProviderResolver extends _LolPlusAdapterBase {
  const CuevanaProviderResolver();

  @override
  String get id => 'lolplus_cuevana';

  @override
  String get displayName => 'Cuevana';

  @override
  int get priority => 15;

  @override
  Set<String> get supportedMediaTypes => const {'movie', 'tv'};

  @override
  Stream<Map<String, dynamic>> scrape({
    required int tmdbId,
    required bool isMovie,
    required int season,
    required int episode,
  }) {
    return CuevanaService.scrape(
      tmdbId: tmdbId,
      isMovie: isMovie,
      season: season,
      episode: episode,
    ).map((s) => s.toModalMap());
  }
}

class TioPlusProviderResolver extends _LolPlusAdapterBase {
  const TioPlusProviderResolver();

  @override
  String get id => 'lolplus_tioplus';

  @override
  String get displayName => 'TioPlus';

  @override
  int get priority => 15;

  @override
  Set<String> get supportedMediaTypes => const {'movie', 'tv', 'anime'};

  @override
  Stream<Map<String, dynamic>> scrape({
    required int tmdbId,
    required bool isMovie,
    required int season,
    required int episode,
  }) {
    return TioplusService.scrape(
      tmdbId: tmdbId,
      isMovie: isMovie,
      season: season,
      episode: episode,
    ).map((s) => s.toModalMap());
  }
}

class PelisPlusProviderResolver extends _LolPlusAdapterBase {
  const PelisPlusProviderResolver();

  @override
  String get id => 'lolplus_pelisplus';

  @override
  String get displayName => 'PelisPlus';

  @override
  int get priority => 15;

  @override
  Set<String> get supportedMediaTypes => const {'movie', 'tv'};

  @override
  Stream<Map<String, dynamic>> scrape({
    required int tmdbId,
    required bool isMovie,
    required int season,
    required int episode,
  }) {
    return PelisPlusService.scrape(
      tmdbId: tmdbId,
      isMovie: isMovie,
      season: season,
      episode: episode,
    );
  }
}

class CinecalidadProviderResolver extends _LolPlusAdapterBase {
  const CinecalidadProviderResolver();

  @override
  String get id => 'lolplus_cinecalidad';

  @override
  String get displayName => 'Cinecalidad';

  @override
  int get priority => 15;

  @override
  Set<String> get supportedMediaTypes => const {'movie', 'tv'};

  @override
  Stream<Map<String, dynamic>> scrape({
    required int tmdbId,
    required bool isMovie,
    required int season,
    required int episode,
  }) {
    return CinecalidadService.scrape(
      tmdbId: tmdbId,
      isMovie: isMovie,
      season: season,
      episode: episode,
    ).map((s) => s.toModalMap());
  }
}
