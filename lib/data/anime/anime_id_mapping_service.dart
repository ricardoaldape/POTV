import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final animeIdMappingServiceProvider = Provider<AnimeIdMappingService>((ref) {
  return AnimeIdMappingService(
    Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 12),
        headers: const {
          'Accept': 'application/json',
          'User-Agent': 'POTV/0.1 (Android)',
        },
      ),
    ),
  );
});

class AnimeEpisodeMapping {
  final int anilistId;
  final String? imdbId;
  final int absoluteEpisode;
  final int? season;
  final int? episode;

  const AnimeEpisodeMapping({
    required this.anilistId,
    required this.imdbId,
    required this.absoluteEpisode,
    required this.season,
    required this.episode,
  });

  bool get canUseSeriesProtocol =>
      imdbId != null && season != null && episode != null;
}

class AnimeIdMappingService {
  static const _base = 'https://api.ani.zip/mappings';

  final Dio _dio;
  final Map<int, Map<String, dynamic>> _cache = {};

  AnimeIdMappingService(this._dio);

  Future<AnimeEpisodeMapping?> mapEpisode({
    required int anilistId,
    required int absoluteEpisode,
  }) async {
    final raw = await _mapping(anilistId);
    if (raw == null) return null;

    final mappings = raw['mappings'];
    final imdbId = mappings is Map
        ? _text(mappings['imdb_id'])
        : null;

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

    return AnimeEpisodeMapping(
      anilistId: anilistId,
      imdbId: imdbId,
      absoluteEpisode: absoluteEpisode,
      season: _int(episodeRaw?['seasonNumber']),
      episode: _int(episodeRaw?['episodeNumber']),
    );
  }

  Future<Map<String, dynamic>?> _mapping(int anilistId) async {
    final cached = _cache[anilistId];
    if (cached != null) return cached;

    try {
      final response = await _dio.get<Map<String, dynamic>>(
        _base,
        queryParameters: {
          'anilist_id': anilistId,
        },
      );
      final data = response.data;
      if (data == null) return null;
      _cache[anilistId] = data;
      return data;
    } on DioException {
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
