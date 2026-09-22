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

  final Dio _dio;

  TmdbRepository(this._dio);

  Future<List<MediaItem>> search(String query) async {
    final key = _requireKey();

    final response = await _dio.get<Map<String, dynamic>>(
      '$_apiBase/search/multi',
      queryParameters: {
        'api_key': key,
        'query': query.trim(),
        'language': 'es-MX',
        'include_adult': false,
      },
    );

    return _mapList(
      response.data?['results'],
      allowMixed: true,
    );
  }

  Future<List<MediaItem>> trending(MediaType type) async {
    final key = _requireKey();
    final endpoint = type == MediaType.movie ? 'movie' : 'tv';

    final response = await _dio.get<Map<String, dynamic>>(
      '$_apiBase/trending/$endpoint/week',
      queryParameters: {
        'api_key': key,
        'language': 'es-MX',
      },
    );

    return _mapList(
      response.data?['results'],
      forcedType: type,
    );
  }

  Future<List<MediaItem>> popular(MediaType type) async {
    final key = _requireKey();
    final endpoint = type == MediaType.movie ? 'movie' : 'tv';

    final response = await _dio.get<Map<String, dynamic>>(
      '$_apiBase/$endpoint/popular',
      queryParameters: {
        'api_key': key,
        'language': 'es-MX',
        'region': 'MX',
        'page': 1,
      },
    );

    return _mapList(
      response.data?['results'],
      forcedType: type,
    );
  }

  Future<List<MediaItem>> discoverByGenre(
    MediaType type,
    int genreId,
  ) async {
    final key = _requireKey();
    final endpoint = type == MediaType.movie ? 'movie' : 'tv';

    final response = await _dio.get<Map<String, dynamic>>(
      '$_apiBase/discover/$endpoint',
      queryParameters: {
        'api_key': key,
        'language': 'es-MX',
        'region': 'MX',
        'sort_by': 'popularity.desc',
        'with_genres': genreId,
        'include_adult': false,
        'page': 1,
      },
    );

    return _mapList(
      response.data?['results'],
      forcedType: type,
    );
  }

  String _requireKey() {
    final key = AppConfig.tmdbApiKey.trim();
    if (key.isEmpty) {
      throw StateError(
        'TMDB_API_KEY no está configurada en esta compilación.',
      );
    }
    return key;
  }

  List<MediaItem> _mapList(
    Object? raw, {
    MediaType? forcedType,
    bool allowMixed = false,
  }) {
    if (raw is! List) return const [];

    final items = <MediaItem>[];
    for (final value in raw) {
      if (value is! Map<String, dynamic>) continue;
      final item = _mapItem(
        value,
        forcedType: forcedType,
        allowMixed: allowMixed,
      );
      if (item != null) items.add(item);
    }
    return items;
  }

  MediaItem? _mapItem(
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

    if (type == null) return null;

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
      poster: _imageUri(raw['poster_path'], _imageBase),
      backdrop: _imageUri(raw['backdrop_path'], _backdropBase),
    );
  }

  Uri? _imageUri(Object? value, String base) {
    final path = _text(value);
    return path == null ? null : Uri.parse('$base$path');
  }

  String? _text(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
}
