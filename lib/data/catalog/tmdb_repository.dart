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

class TmdbRepository {
  static const _apiBase = 'https://api.themoviedb.org/3';
  static const _imageBase = 'https://image.tmdb.org/t/p/w500';

  final Dio _dio;

  TmdbRepository(this._dio);

  Future<List<MediaItem>> search(String query) async {
    final key = AppConfig.tmdbApiKey.trim();
    if (key.isEmpty) {
      throw StateError(
        'TMDB_API_KEY no está configurada en esta compilación.',
      );
    }

    final response = await _dio.get<Map<String, dynamic>>(
      '$_apiBase/search/multi',
      queryParameters: {
        'api_key': key,
        'query': query.trim(),
        'language': 'es-MX',
        'include_adult': false,
      },
    );

    final raw = response.data?['results'];
    if (raw is! List) return const [];

    final items = <MediaItem>[];
    for (final value in raw) {
      if (value is! Map<String, dynamic>) continue;
      final item = _mapItem(value);
      if (item != null) items.add(item);
    }
    return items;
  }

  MediaItem? _mapItem(Map<String, dynamic> raw) {
    final id = raw['id'];
    final mediaType = raw['media_type']?.toString();
    if (id is! int || (mediaType != 'movie' && mediaType != 'tv')) {
      return null;
    }

    final type = mediaType == 'movie' ? MediaType.movie : MediaType.tv;
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
      poster: _imageUri(raw['poster_path']),
      backdrop: _imageUri(raw['backdrop_path']),
    );
  }

  Uri? _imageUri(Object? value) {
    final path = _text(value);
    return path == null ? null : Uri.parse('$_imageBase$path');
  }

  String? _text(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
}
