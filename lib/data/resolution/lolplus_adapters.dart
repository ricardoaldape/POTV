import '../../domain/models/stream_candidate.dart';
import '../../domain/resolution/provider_resolver.dart';
import '../anime/anime_id_mapping_service.dart';
import '../debug/debug_log_provider.dart';
import '../extractors/native_resolvers.dart';
import '../extractors/cinesrc_extractor.dart';
import '../extractors/vidsrc_extractor.dart';
import '../extractors/multi_embed_extractor.dart';
import '../extractors/cuevana_extractor.dart';
import '../extractors/tioplus_extractor.dart';
import '../extractors/pelisplus_extractor.dart';
import '../extractors/cinecalidad_extractor.dart';
import '../extractors/hackstore_extractor.dart';
import '../extractors/unlimplay_extractor.dart';
import '../extractors/poseidon_extractor.dart';
import '../extractors/pelispedia_extractor.dart';
import '../extractors/seriesmetro_extractor.dart';
import '../extractors/smartpelis_extractor.dart';
import '../extractors/embed69_extractor.dart';

/// Base adapter that wraps a LolPlus-style extractor stream and converts
/// results into `StreamCandidate`s using `NativeResolvers` when possible.
abstract class _LolPlusAdapterBase extends ProviderResolver {
  final AnimeIdMappingService? animeMapping;
  const _LolPlusAdapterBase({this.animeMapping});

  Stream<Map<String, dynamic>> scrape({
    required int tmdbId,
    required bool isMovie,
    required int season,
    required int episode,
  });

  @override
  Future<List<StreamCandidate>> resolve(ProviderResolveRequest request) async {
    addDebugLog(
      '[Adapter $id] resolve mediaType=${request.mediaType} mediaId=${request.mediaId} title="${request.title}"',
    );

    // Si es anime, mapear AniList → TMDB
    if (request.mediaType == 'anime' && animeMapping != null) {
      final anilistId = int.tryParse(request.mediaId);
      final absoluteEp = request.episode ?? 1;
      addDebugLog('[Adapter $id] ANIME branch - anilistId=$anilistId absoluteEp=$absoluteEp');

      if (anilistId == null || anilistId <= 0) {
        addDebugLog('[Adapter $id] ANIME branch returns empty: anilistId inválido o no positivo');
        return const [];
      }

      final mapped = await animeMapping!.mapEpisode(
        anilistId: anilistId,
        absoluteEpisode: absoluteEp,
        title: request.title,
      );
      if (mapped == null) {
        addDebugLog('[Adapter $id] ANIME branch returns empty: mapeo de AniList a TMDB no encontrado');
        return const [];
      }
      if (mapped.tmdbId == null) {
        addDebugLog('[Adapter $id] ANIME branch returns empty: mapped.tmdbId es nulo');
        return const [];
      }

      addDebugLog(
        '[Adapter $id] ANIME mapeado -> tmdbId=${mapped.tmdbId} season=${mapped.season ?? 1} episode=${mapped.episode ?? 1}',
      );

      return _resolveStream(
        tmdbId: mapped.tmdbId!,
        isMovie: false,
        season: mapped.season ?? 1,
        episode: mapped.episode ?? 1,
      );
    }

    final tmdbId = int.tryParse(request.mediaId);
    if (tmdbId == null || tmdbId <= 0) return const [];

    final isMovie = request.mediaType == 'movie';
    final season = request.season ?? 1;
    final episode = request.episode ?? 1;

    return _resolveStream(
      tmdbId: tmdbId,
      isMovie: isMovie,
      season: season,
      episode: episode,
    );
  }

  Future<List<StreamCandidate>> _resolveStream({
    required int tmdbId,
    required bool isMovie,
    required int season,
    required int episode,
  }) async {
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
          timeout: const Duration(seconds: 12),
        );

        if (resolved != null && resolved.url.isNotEmpty) {
          candidates.add(StreamCandidate(
            id: '${id}_${candidates.length}',
            label: servidorNombre,
            uri: Uri.parse(resolved.url),
            language: idioma,
            quality: (resolved.quality.isNotEmpty ? resolved.quality : calidad),
                backend: PlaybackBackend.native,
                headers: {
                  'User-Agent':
                      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                  'Referer': _refererForStream(resolved.url),
                  ...resolved.headers,
                },
          ));
        } else {
          // No se pudo resolver nativamente → conservar solo si la entrada
          // ya indica `backend: 'native'` o si la URL parece apuntar a m3u8/mp4.
          final incomingBackend = (m['backend'] is String) ? m['backend'] as String : '';
          final headersRaw = m['headers'];
          final headers = <String, String>{};
          if (headersRaw is Map) {
            headersRaw.forEach((k, v) {
              try {
                headers[k.toString()] = v.toString();
              } catch (_) {}
            });
          }

          final isDirectMedia = servidorUrl.toLowerCase().contains('.m3u8') || servidorUrl.toLowerCase().endsWith('.mp4');
          if (incomingBackend == 'native' || isDirectMedia) {
            try {
              candidates.add(StreamCandidate(
                id: '${id}_${candidates.length}',
                label: servidorNombre,
                uri: Uri.parse(servidorUrl),
                language: idioma,
                quality: calidad,
                backend: PlaybackBackend.native,
                headers: {
                  'User-Agent':
                      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                  'Referer': _refererForStream(servidorUrl),
                  ...headers,
                },
              ));
            } catch (_) {
              // ignore malformed url
            }
          } else {
            // No se pudo resolver nativamente → usar WebView como fallback.
            // El player mostrará la página del embed con el hidden probe
            // que ya bloquea popups (VPN, ads) antes de mostrarlos.
            try {
              candidates.add(StreamCandidate(
                id: '${id}_${candidates.length}',
                label: '$servidorNombre (WebView)',
                uri: Uri.parse(servidorUrl),
                language: idioma,
                quality: calidad,
                backend: PlaybackBackend.webView,
                headers: {
                  'User-Agent':
                      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                  'Referer': _refererForStream(servidorUrl),
                },
                directWebView: true,
              ));
            } catch (_) {
              // URL malformada → sí descartar
            }
          }
        }
      } catch (_) {
        // On error, skip this server to avoid WebView popups.
        continue;
      }
    }

    return candidates;
  }
}

/// Devuelve el Referer correcto según el host del stream.
/// Sin esto, CDNs como tylenews.com o turboviplay.com bloquean con 403.
String _refererForStream(String url) {
  try {
    final uri = Uri.parse(url);
    final host = uri.host.toLowerCase();

    // TioPlus / CDNs
    if (host.contains('tylenews') ||
        host.contains('turbovi') ||
        host.contains('uptosharez')) {
      return 'https://tioplus.app/';
    }
    // Filemoon
    if (host.contains('filemoon') || host.contains('bysedikamoum')) {
      return 'https://filemoon.sx/';
    }
    // StreamWish / Vibuxer
    if (host.contains('streamwish') ||
        host.contains('hglink') ||
        host.contains('vibuxer') ||
        host.contains('hgplaycdn')) {
      return 'https://streamwish.to/';
    }
    // VidHide / Callistanise
    if (host.contains('vidhide') ||
        host.contains('callistanise') ||
        host.contains('filelions')) {
      return 'https://vidhidepro.com/';
    }
    // VOE
    if (host.contains('voe')) {
      return 'https://voe.sx/';
    }
    // Doodstream
    if (host.contains('dood') || host.contains('dsvplay')) {
      return 'https://dood.to/';
    }
    // PelisPlus / Cuevana
    if (host.contains('pelisplus') || host.contains('pelisplushd')) {
      return 'https://pelisplushd.bz/';
    }
    if (host.contains('cuevana')) {
      return 'https://wv3.cuevana3.eu/';
    }
    if (host.contains('cinecalidad')) {
      return 'https://cinecalidad.am/';
    }
    // Fallback: el propio host
    return '${uri.scheme}://${uri.host}/';
  } catch (_) {
    return '';
  }
}

class CuevanaProviderResolver extends _LolPlusAdapterBase {
  const CuevanaProviderResolver({super.animeMapping});

  @override
  String get id => 'lolplus_cuevana';

  @override
  String get displayName => 'Cuevana';

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
    return CuevanaService.scrape(
      tmdbId: tmdbId,
      isMovie: isMovie,
      season: season,
      episode: episode,
    ).map((s) => s.toModalMap());
  }
}

class TioPlusProviderResolver extends _LolPlusAdapterBase {
  const TioPlusProviderResolver({super.animeMapping});

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
  const PelisPlusProviderResolver({super.animeMapping});

  @override
  String get id => 'lolplus_pelisplus';

  @override
  String get displayName => 'PelisPlus';

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
    return PelisPlusService.scrape(
      tmdbId: tmdbId,
      isMovie: isMovie,
      season: season,
      episode: episode,
    );
  }
}

class CinecalidadProviderResolver extends _LolPlusAdapterBase {
  const CinecalidadProviderResolver({super.animeMapping});

  @override
  String get id => 'lolplus_cinecalidad';

  @override
  String get displayName => 'Cinecalidad';

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
    return CinecalidadService.scrape(
      tmdbId: tmdbId,
      isMovie: isMovie,
      season: season,
      episode: episode,
    ).map((s) => s.toModalMap());
  }
}

class CineSrcProviderResolver extends _LolPlusAdapterBase {
  const CineSrcProviderResolver({super.animeMapping});

  @override
  String get id => 'lolplus_cinesrc';

  @override
  String get displayName => 'CineSrc';

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
    return CineSrcService.scrape(
      tmdbId: tmdbId,
      isMovie: isMovie,
      season: season,
      episode: episode,
    ).map((s) => s.toModalMap());
  }
}

class VidSrcProviderResolver extends _LolPlusAdapterBase {
  const VidSrcProviderResolver({super.animeMapping});

  @override
  String get id => 'lolplus_vidsrc';

  @override
  String get displayName => 'VidSrc';

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
    return VidSrcService.scrape(
      tmdbId: tmdbId,
      isMovie: isMovie,
      season: season,
      episode: episode,
    );
  }
}

class MultiEmbedProviderResolver extends _LolPlusAdapterBase {
  const MultiEmbedProviderResolver({super.animeMapping});

  @override
  String get id => 'lolplus_multiembed';

  @override
  String get displayName => 'Multi Embed';

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
    return MultiEmbedService.scrape(
      tmdbId: tmdbId,
      isMovie: isMovie,
      season: season,
      episode: episode,
    );
  }
}

class HackStoreProviderResolver extends _LolPlusAdapterBase {
  const HackStoreProviderResolver({super.animeMapping});

  @override
  String get id => 'lolplus_hackstore';

  @override
  String get displayName => 'HackStore';

  @override
  int get priority => 60;

  @override
  Set<String> get supportedMediaTypes => const {'movie', 'tv', 'anime'};

  @override
  Stream<Map<String, dynamic>> scrape({
    required int tmdbId,
    required bool isMovie,
    required int season,
    required int episode,
  }) {
    return HackStoreService.scrape(
      tmdbId: tmdbId,
      isMovie: isMovie,
      season: season,
      episode: episode,
    );
  }
}

class UnlimplayProviderResolver extends _LolPlusAdapterBase {
  const UnlimplayProviderResolver({super.animeMapping});

  @override
  String get id => 'lolplus_unlimplay';

  @override
  String get displayName => 'Unlimplay';

  @override
  int get priority => 16;

  @override
  Set<String> get supportedMediaTypes => const {'movie', 'tv', 'anime'};

  @override
  Stream<Map<String, dynamic>> scrape({
    required int tmdbId,
    required bool isMovie,
    required int season,
    required int episode,
  }) {
    return UnlimplayService.scrape(
      tmdbId: tmdbId,
      isMovie: isMovie,
      season: season,
      episode: episode,
    ).map((s) => s.toModalMap());
  }
}

class PoseidonProviderResolver extends _LolPlusAdapterBase {
  const PoseidonProviderResolver({super.animeMapping});

  @override
  String get id => 'lolplus_poseidon';

  @override
  String get displayName => 'Poseidon';

  @override
  int get priority => 20;

  @override
  Set<String> get supportedMediaTypes => const {'movie', 'tv', 'anime'};

  @override
  Stream<Map<String, dynamic>> scrape({
    required int tmdbId,
    required bool isMovie,
    required int season,
    required int episode,
  }) {
    return PoseidonService.scrape(
      tmdbId: tmdbId,
      isMovie: isMovie,
      season: season,
      episode: episode,
    ).map((s) => s.toModalMap());
  }
}

class PelispediaProviderResolver extends _LolPlusAdapterBase {
  const PelispediaProviderResolver({super.animeMapping});

  @override
  String get id => 'lolplus_pelispedia';

  @override
  String get displayName => 'Pelispedia';

  @override
  int get priority => 20;

  @override
  Set<String> get supportedMediaTypes => const {'movie', 'tv'};

  @override
  Stream<Map<String, dynamic>> scrape({
    required int tmdbId,
    required bool isMovie,
    required int season,
    required int episode,
  }) {
    return PelispediaService.scrape(
      tmdbId: tmdbId,
      isMovie: isMovie,
      season: season,
      episode: episode,
    ).map((s) => s.toModalMap());
  }
}

class SeriesMetroProviderResolver extends _LolPlusAdapterBase {
  const SeriesMetroProviderResolver({super.animeMapping});

  @override
  String get id => 'lolplus_seriesmetro';

  @override
  String get displayName => 'SeriesMetro';

  @override
  int get priority => 20;

  @override
  Set<String> get supportedMediaTypes => const {'movie', 'tv'};

  @override
  Stream<Map<String, dynamic>> scrape({
    required int tmdbId,
    required bool isMovie,
    required int season,
    required int episode,
  }) {
    return SeriesMetroService.scrape(
      tmdbId: tmdbId,
      isMovie: isMovie,
      season: season,
      episode: episode,
    ).map((s) => s.toModalMap());
  }
}

class SmartPelisProviderResolver extends _LolPlusAdapterBase {
  const SmartPelisProviderResolver({super.animeMapping});

  @override
  String get id => 'lolplus_smartpelis';

  @override
  String get displayName => 'SmartPelis';

  @override
  int get priority => 20;

  @override
  Set<String> get supportedMediaTypes => const {'movie', 'tv'};

  @override
  Stream<Map<String, dynamic>> scrape({
    required int tmdbId,
    required bool isMovie,
    required int season,
    required int episode,
  }) {
    return SmartPelisService.scrape(
      tmdbId: tmdbId,
      isMovie: isMovie,
      season: season,
      episode: episode,
    ).map((s) => s.toModalMap());
  }
}

class Embed69ProviderResolver extends _LolPlusAdapterBase {
  const Embed69ProviderResolver({super.animeMapping});

  @override
  String get id => 'lolplus_embed69';

  @override
  String get displayName => 'Embed69';

  @override
  int get priority => 20;

  @override
  Set<String> get supportedMediaTypes => const {'movie', 'tv', 'anime'};

  @override
  Stream<Map<String, dynamic>> scrape({
    required int tmdbId,
    required bool isMovie,
    required int season,
    required int episode,
  }) {
    return Embed69Service.scrape(
      tmdbId: tmdbId,
      isMovie: isMovie,
      season: season,
      episode: episode,
    ).map((s) => s.toModalMap());
  }
}
