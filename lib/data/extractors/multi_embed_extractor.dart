import 'dart:async';

/// Múltiples embeds con URL directa basada en TMDB ID.
/// No requieren scraping.
class MultiEmbedService {
  MultiEmbedService._();

  static const String _vsEmbedBase = 'https://vsembed.ru';
  static const String _zxcPrimeBase = 'https://player.zxcprime.xyz';
  static const String _vimeusBase = 'https://vimeus.com';
  static const String _vimeusKey = 'KUDU-EYQ76rbZwNu7hun16C4HX0K6qy77hZw4CaveiI';

  static Stream<Map<String, dynamic>> scrape({
    required int tmdbId,
    required bool isMovie,
    int season = 1,
    int episode = 1,
  }) async* {
    if (tmdbId <= 0) return;

    // VsEmbed (inglés + subtítulos)
    yield {
      'servidor_url': isMovie
          ? '$_vsEmbedBase/embed/movie?tmdb=$tmdbId&ds_lang=es&auto=1'
          : '$_vsEmbedBase/embed/tv?tmdb=$tmdbId&season=$season&episode=$episode&color=e600e6&ds_lang=es&auto=1',
      'servidor_nombre': 'VsEmbed',
      'calidad': 'HD',
      'idioma': 'en_US',
      'es_vsembed': true,
      'backend': 'webView',
    };

    // ZxcPrime
    yield {
      'servidor_url': isMovie
          ? '$_zxcPrimeBase/player/movie/$tmdbId?autoplay=true&server=0&back=false&dubLang=esla'
          : '$_zxcPrimeBase/player/tv/$tmdbId/$season/$episode?autoplay=true&server=0&back=false&dubLang=esla',
      'servidor_nombre': 'ZxcPrime',
      'calidad': 'HD',
      'idioma': 'en_US',
      'es_zxcprime': true,
      'backend': 'webView',
    };

    // Vimeus
    yield {
      'servidor_url': isMovie
          ? '$_vimeusBase/e/movie?tmdb=$tmdbId&view_key=$_vimeusKey&title=+&theme=minimal'
          : '$_vimeusBase/e/serie?tmdb=$tmdbId&se=$season&ep=$episode&view_key=$_vimeusKey&title=+&theme=minimal',
      'servidor_nombre': 'Vimeus',
      'calidad': 'HD',
      'idioma': 'es_MX',
      'es_vimeus': true,
      'backend': 'webView',
    };
  }
}
