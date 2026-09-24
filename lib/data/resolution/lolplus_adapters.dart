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
            // No se pudo resolver nativamente → descartar para evitar popups en WebView
            continue;
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
