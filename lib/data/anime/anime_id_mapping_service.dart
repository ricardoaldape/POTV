import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../debug/debug_log_provider.dart';

final animeIdMappingServiceProvider = Provider<AnimeIdMappingService>((ref) {
  return AnimeIdMappingService(
    Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 12),
        headers: const {
          'Accept': 'application/json',
          'User-Agent': 'Mozilla/5.0 POTV/0.5 (Android)',
        },
      ),
    ),
  );
});

class AnimeEpisodeMapping {
  final int anilistId;
  final String? imdbId;
  final int? tmdbId;
  final int absoluteEpisode;
  final int? season;
  final int? episode;

  const AnimeEpisodeMapping({
    required this.anilistId,
    required this.imdbId,
    required this.tmdbId,
    required this.absoluteEpisode,
    required this.season,
    required this.episode,
  });

  bool get canUseSeriesProtocol =>
      imdbId != null && season != null && episode != null;
}

class AnimeIdMappingService {
  static const _aniZipBase = 'https://api.ani.zip/mappings';
  static const _cinemetaBase = 'https://v3-cinemeta.strem.io';

  final Dio _dio;
  final Map<int, Map<String, dynamic>> _cache = {};

  AnimeIdMappingService(this._dio);

  Future<AnimeEpisodeMapping?> mapEpisode({
    required int anilistId,
    required int absoluteEpisode,
    String? title,
  }) async {
    addDebugLog('[AnimeMapping] mapEpisode anilist=$anilistId ep=$absoluteEpisode title="$title"');

    final raw = await _mapping(anilistId);
    final direct = _fromAniZip(
      anilistId: anilistId,
      absoluteEpisode: absoluteEpisode,
      raw: raw,
    );

    if (direct?.canUseSeriesProtocol == true) return direct;
    if (title == null || title.trim().isEmpty) {
      addDebugLog('[AnimeMapping] retornando direct: tmdbId=${direct?.tmdbId}');
      return direct;
    }

    // Si el mapping directo no dio tmdbId, intentar buscar por título
    if (direct?.tmdbId == null && title.trim().isNotEmpty) {
      final searched = await searchByTitleInTmdb(
        anilistId: anilistId,
        title: title.trim(),
        absoluteEpisode: absoluteEpisode,
      );
      if (searched != null) return searched;
    }

    addDebugLog('[AnimeMapping] direct mapping null, intentando cinemeta');
    return _mapViaCinemeta(
      anilistId: anilistId,
      absoluteEpisode: absoluteEpisode,
      title: title.trim(),
      fallback: direct,
    );
  }

  AnimeEpisodeMapping? _fromAniZip({
    required int anilistId,
    required int absoluteEpisode,
    required Map<String, dynamic>? raw,
  }) {
    if (raw == null) return null;

    final mappings = raw['mappings'];
    final imdbId = mappings is Map ? _text(mappings['imdb_id']) : null;
    final tmdbId = mappings is Map ? _int(mappings['tmdb_id']) : null;
    final episodes = raw['episodes'];

    Map<String, dynamic>? episodeRaw;
    if (episodes is Map) {
      final value = episodes[absoluteEpisode.toString()];
      if (value is Map<String, dynamic>) {
        episodeRaw = value;
      } else if (value is Map) {
        episodeRaw = value.map(
          (key, value) => MapEntry(key.toString(), value),
        );
      }
    }

    addDebugLog(
      '[AnimeMapping] _fromAniZip anilist=$anilistId imdb=$imdbId tmdb=$tmdbId season=${episodeRaw?['seasonNumber']} ep=${episodeRaw?['episodeNumber']}',
    );

    return AnimeEpisodeMapping(
      anilistId: anilistId,
      imdbId: imdbId,
      tmdbId: tmdbId,
      absoluteEpisode: absoluteEpisode,
      season: _int(episodeRaw?['seasonNumber']),
      episode: _int(episodeRaw?['episodeNumber']),
    );
  }

  Future<AnimeEpisodeMapping?> _mapViaCinemeta({
    required int anilistId,
    required int absoluteEpisode,
    required String title,
    required AnimeEpisodeMapping? fallback,
  }) async {
    try {
      final imdbId = fallback?.imdbId ?? await _findCinemetaImdbId(title);
      if (imdbId == null) return fallback;

      final response = await _dio.get<Map<String, dynamic>>(
        '$_cinemetaBase/meta/series/$imdbId.json',
        options: Options(responseType: ResponseType.json),
      );
      final meta = response.data?['meta'];
      if (meta is! Map) return fallback;

      final videos = meta['videos'];
      if (videos is! List) return fallback;

      final regular = <Map<dynamic, dynamic>>[];
      for (final value in videos) {
        if (value is! Map) continue;
        final season = _int(value['season']);
        final episode = _int(value['episode']);
        if (season == null || season < 1 || episode == null || episode < 1) {
          continue;
        }
        regular.add(value);
      }
      if (absoluteEpisode < 1 || absoluteEpisode > regular.length) {
        return fallback;
      }

      final selected = regular[absoluteEpisode - 1];
      return AnimeEpisodeMapping(
        anilistId: anilistId,
        imdbId: imdbId,
        tmdbId: fallback?.tmdbId,
        absoluteEpisode: absoluteEpisode,
        season: _int(selected['season']),
        episode: _int(selected['episode']),
      );
    } on DioException {
      return fallback;
    }
  }

  Future<String?> _findCinemetaImdbId(String title) async {
    final encoded = Uri.encodeComponent(title);
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '$_cinemetaBase/catalog/series/top/search=$encoded.json',
        options: Options(responseType: ResponseType.json),
      );
      final metas = response.data?['metas'];
      if (metas is! List) return null;

      final target = title.toLowerCase();
      Map<dynamic, dynamic>? first;
      for (final value in metas) {
        if (value is! Map) continue;
        first ??= value;
        final name = _text(value['name'])?.toLowerCase();
        if (name == target) {
          final exact = _text(value['imdb_id']) ?? _text(value['id']);
          if (exact?.startsWith('tt') == true) return exact;
        }
      }

      final candidate =
          first == null ? null : _text(first['imdb_id']) ?? _text(first['id']);
      return candidate?.startsWith('tt') == true ? candidate : null;
    } on DioException {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _mapping(int anilistId) async {
    final cached = _cache[anilistId];
    if (cached != null) return cached;

    try {
      final response = await _dio.get<Map<String, dynamic>>(
        _aniZipBase,
        queryParameters: {'anilist_id': anilistId},
      );
      final data = response.data;
      if (data == null) return null;
      _cache[anilistId] = data;
      return data;
    } on DioException {
      return null;
    }
  }

  /// Fallback: busca el anime en TMDB por título y devuelve el primer resultado.
  /// Retorna el TMDB ID y temporada/episodio asumiendo que es la primera temporada.
  Future<AnimeEpisodeMapping?> searchByTitleInTmdb({
    required int anilistId,
    required String title,
    required int absoluteEpisode,
  }) async {
    try {
      addDebugLog('[AnimeMapping] searchByTitleInTmdb "$title"');

      final response = await _dio.get<Map<String, dynamic>>(
        'https://api.themoviedb.org/3/search/tv',
        queryParameters: {
          'api_key': 'a2d9bbed370d9f678e34006f8750a5a5',
          'query': title,
          'language': 'es-MX',
        },
        options: Options(responseType: ResponseType.json),
      );
      addDebugLog(
        '[AnimeMapping] TMDB status=${response.statusCode} results=${(response.data?['results'] as List?)?.length ?? 0}',
      );

      final results = response.data?['results'];
      if (results is! List || results.isEmpty) {
        addDebugLog('[AnimeMapping] searchByTitleInTmdb return null: resultados vacíos');
        return null;
      }

      final first = results.first;
      if (first is! Map) {
        addDebugLog('[AnimeMapping] searchByTitleInTmdb return null: primer resultado no es un mapa');
        return null;
      }
      final tmdbId = first['id'];
      if (tmdbId is! int || tmdbId <= 0) {
        addDebugLog('[AnimeMapping] searchByTitleInTmdb return null: tmdbId inválido ($tmdbId)');
        return null;
      }

      return AnimeEpisodeMapping(
        anilistId: anilistId,
        imdbId: null,
        tmdbId: tmdbId,
        absoluteEpisode: absoluteEpisode,
        season: 1,
        episode: absoluteEpisode,
      );
    } on DioException {
      addDebugLog('[AnimeMapping] searchByTitleInTmdb return null: error HTTP en TMDB');
      return null;
    }
  }

  int? _int(Object? value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }

  String? _text(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
}
