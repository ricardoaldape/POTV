import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../domain/models/media_item.dart';

final tmdbRepositoryProvider = Provider<TmdbRepository>((ref) {
  return TmdbRepository(Dio());
});

final mediaSearchProvider =
    FutureProvider.autoDispose.family<List<MediaItem>, String>((ref, query) {
  if (query.trim().length < 2) return Future.value(const []);
  return ref.read(tmdbRepositoryProvider).search(query);
});

final homeTrendingProvider =
    FutureProvider.autoDispose.family<List<MediaItem>, MediaType>((ref, type) {
  return ref.read(tmdbRepositoryProvider).trending(type);
});

final homePopularProvider =
    FutureProvider.autoDispose.family<List<MediaItem>, MediaType>((ref, type) {
  return ref.read(tmdbRepositoryProvider).popular(type);
});

final homeGenreProvider = FutureProvider.autoDispose
    .family<List<MediaItem>, ({MediaType type, int genreId})>((ref, request) {
  return ref
      .read(tmdbRepositoryProvider)
      .discoverByGenre(request.type, request.genreId);
});

class TmdbRepository {
  static const _apiBase = 'https://api.themoviedb.org/3';
  static const _imageBase = 'https://image.tmdb.org/t/p/w500';
  static const _backdropBase = 'https://image.tmdb.org/t/p/w1280';
  static const _cinemetaBase = 'https://v3-cinemeta.strem.io';

  final Dio _dio;

  TmdbRepository(this._dio);

  bool get _hasTmdbKey => AppConfig.tmdbApiKey.trim().isNotEmpty;

  Future<List<MediaItem>> search(String query) async {
    if (!_hasTmdbKey) return _cinemetaSearch(query);

    final response = await _dio.get<Map<String, dynamic>>(
      '$_apiBase/search/multi',
      queryParameters: {
        'api_key': AppConfig.tmdbApiKey.trim(),
        'query': query.trim(),
        'language': 'es-MX',
        'include_adult': false,
      },
    );

    return _mapTmdbList(
      response.data?['results'],
      allowMixed: true,
    );
  }

  Future<List<MediaItem>> trending(MediaType type) async {
    if (!_hasTmdbKey) return _cinemetaCatalog(type);

    final endpoint = _endpoint(type);
    final response = await _dio.get<Map<String, dynamic>>(
      '$_apiBase/trending/$endpoint/week',
      queryParameters: {
        'api_key': AppConfig.tmdbApiKey.trim(),
        'language': 'es-MX',
      },
    );

    return _mapTmdbList(
      response.data?['results'],
      forcedType: type,
    );
  }

  Future<List<MediaItem>> popular(MediaType type) async {
    if (!_hasTmdbKey) return _cinemetaCatalog(type);

    final endpoint = _endpoint(type);
    final response = await _dio.get<Map<String, dynamic>>(
      '$_apiBase/$endpoint/popular',
      queryParameters: {
        'api_key': AppConfig.tmdbApiKey.trim(),
        'language': 'es-MX',
        'region': 'MX',
        'page': 1,
      },
    );

    return _mapTmdbList(
      response.data?['results'],
      forcedType: type,
    );
  }

  Future<List<MediaItem>> discoverByGenre(
    MediaType type,
    int genreId,
  ) async {
    if (!_hasTmdbKey) {
      final genre = _cinemetaGenre(type, genreId);
      return genre == null
          ? _cinemetaCatalog(type)
          : _cinemetaCatalog(type, genre: genre);
    }

    final endpoint = _endpoint(type);
    final response = await _dio.get<Map<String, dynamic>>(
      '$_apiBase/discover/$endpoint',
      queryParameters: {
        'api_key': AppConfig.tmdbApiKey.trim(),
        'language': 'es-MX',
        'region': 'MX',
        'sort_by': 'popularity.desc',
        'with_genres': genreId,
        'include_adult': false,
        'page': 1,
      },
    );

    return _mapTmdbList(
      response.data?['results'],
      forcedType: type,
    );
  }

  Future<List<MediaItem>> _cinemetaSearch(String query) async {
    final encoded = Uri.encodeComponent(query.trim());
    final results = await Future.wait([
      _cinemetaRequest('/catalog/movie/top/search=$encoded.json'),
      _cinemetaRequest('/catalog/series/top/search=$encoded.json'),
    ]);

    return [
      ..._mapCinemetaList(results[0], MediaType.movie),
      ..._mapCinemetaList(results[1], MediaType.tv),
    ];
  }

  Future<List<MediaItem>> _cinemetaCatalog(
    MediaType type, {
    String? genre,
  }) async {
    if (type == MediaType.anime) {
      throw ArgumentError('Anime catalog uses AniList.');
    }

    final resource = type == MediaType.movie ? 'movie' : 'series';
    final extra = genre == null
        ? ''
        : '/genre=${Uri.encodeComponent(genre)}';
    final data = await _cinemetaRequest(
      '/catalog/$resource/top$extra.json',
    );
    return _mapCinemetaList(data, type);
  }

  Future<Object?> _cinemetaRequest(String path) async {
    final response = await _dio.get<Object?>(
      '$_cinemetaBase$path',
      options: Options(
        responseType: ResponseType.json,
        headers: const {
          'Accept': 'application/json',
          'User-Agent': 'Mozilla/5.0 POTV/0.1',
        },
      ),
    );

    if (response.data is Map<String, dynamic>) {
      return (response.data as Map<String, dynamic>)['metas'];
    }
    return null;
  }

  List<MediaItem> _mapCinemetaList(
    Object? raw,
    MediaType type,
  ) {
    if (raw is! List) return const [];

    final items = <MediaItem>[];
    for (final value in raw) {
      if (value is! Map<String, dynamic>) continue;

      final tmdbId = value['moviedb_id'];
      final id = tmdbId is int
          ? tmdbId
          : int.tryParse(tmdbId?.toString() ?? '');
      if (id == null) continue;

      final title = _text(value['name']);
      if (title == null) continue;

      final year = _text(value['year']) ?? _text(value['releaseInfo']);

      items.add(
        MediaItem(
          id: id,
          type: type,
          title: title,
          overview: _text(value['description']),
          year: year,
          poster: _uri(value['poster']),
          backdrop: _uri(value['background']),
        ),
      );
    }
    return items;
  }

  String? _cinemetaGenre(MediaType type, int genreId) {
    if (type == MediaType.movie) {
      return const {
        28: 'Action',
        35: 'Comedy',
        27: 'Horror',
      }[genreId];
    }

    return const {
      18: 'Drama',
      35: 'Comedy',
      10765: 'Sci-Fi',
    }[genreId];
  }

  String _endpoint(MediaType type) => switch (type) {
        MediaType.movie => 'movie',
        MediaType.tv => 'tv',
        MediaType.anime => throw ArgumentError(
            'AniList, not TMDB, is the catalog provider for anime.',
          ),
      };

  List<MediaItem> _mapTmdbList(
    Object? raw, {
    MediaType? forcedType,
    bool allowMixed = false,
  }) {
    if (raw is! List) return const [];

    final items = <MediaItem>[];
    for (final value in raw) {
      if (value is! Map<String, dynamic>) continue;
      final item = _mapTmdbItem(
        value,
        forcedType: forcedType,
        allowMixed: allowMixed,
      );
      if (item != null) items.add(item);
    }
    return items;
  }

  MediaItem? _mapTmdbItem(
    Map<String, dynamic> raw, {
    MediaType? forcedType,
    bool allowMixed = false,
  }) {
    final id = raw['id'];
    if (id is! int) return null;

    MediaType? type = forcedType;
    if (type == null) {
      final mediaType = raw['media_type']?.toString();
      if (mediaType == 'movie') {
        type = MediaType.movie;
      } else if (mediaType == 'tv') {
        type = MediaType.tv;
      } else if (!allowMixed) {
        return null;
      }
    }

    if (type == null || type == MediaType.anime) return null;

    final title = _text(
      type == MediaType.movie ? raw['title'] : raw['name'],
    );
    if (title == null) return null;

    final date = _text(
      type == MediaType.movie
          ? raw['release_date']
          : raw['first_air_date'],
    );

    return MediaItem(
      id: id,
      type: type,
      title: title,
      overview: _text(raw['overview']),
      year: date != null && date.length >= 4 ? date.substring(0, 4) : null,
      poster: _tmdbImageUri(raw['poster_path'], _imageBase),
      backdrop: _tmdbImageUri(raw['backdrop_path'], _backdropBase),
    );
  }

  Uri? _tmdbImageUri(Object? value, String base) {
    final path = _text(value);
    return path == null ? null : Uri.parse('$base$path');
  }

  Uri? _uri(Object? value) {
    final text = _text(value);
    return text == null ? null : Uri.tryParse(text);
  }

  String? _text(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
}
