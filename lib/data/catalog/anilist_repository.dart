import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/text/plain_text.dart';
import '../../domain/models/media_item.dart';

final anilistRepositoryProvider = Provider<AniListRepository>((ref) {
  return AniListRepository(Dio());
});

final animeTrendingProvider =
    FutureProvider.autoDispose<List<MediaItem>>((ref) {
  return ref.read(anilistRepositoryProvider).trending();
});

final animePopularProvider =
    FutureProvider.autoDispose<List<MediaItem>>((ref) {
  return ref.read(anilistRepositoryProvider).popular();
});

final animeGenreProvider =
    FutureProvider.autoDispose.family<List<MediaItem>, String>((ref, genre) {
  return ref.read(anilistRepositoryProvider).byGenre(genre);
});

class AniListRepository {
  static const _endpoint = 'https://graphql.anilist.co';

  final Dio _dio;

  AniListRepository(this._dio);

  Future<List<MediaItem>> trending() {
    return _fetch(sort: 'TRENDING_DESC');
  }

  Future<List<MediaItem>> popular() {
    return _fetch(sort: 'POPULARITY_DESC');
  }

  Future<List<MediaItem>> byGenre(String genre) {
    return _fetch(
      sort: 'POPULARITY_DESC',
      genre: genre,
    );
  }

  Future<List<MediaItem>> _fetch({
    required String sort,
    String? genre,
  }) async {
    const query = r'''
      query ($sort: [MediaSort], $genre: String) {
        Page(page: 1, perPage: 20) {
          media(
            type: ANIME
            sort: $sort
            genre: $genre
            isAdult: false
          ) {
            id
            title {
              romaji
              english
              native
            }
            description(asHtml: false)
            coverImage {
              extraLarge
              large
            }
            bannerImage
            episodes
            startDate {
              year
            }
          }
        }
      }
    ''';

    final response = await _dio.post<Map<String, dynamic>>(
      _endpoint,
      data: {
        'query': query,
        'variables': {
          'sort': [sort],
          'genre': genre,
        },
      },
      options: Options(
        headers: const {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'User-Agent': 'POTV/0.1 (Android)',
        },
      ),
    );

    final page = response.data?['data'];
    if (page is! Map<String, dynamic>) return const [];
    final pageData = page['Page'];
    if (pageData is! Map<String, dynamic>) return const [];
    final raw = pageData['media'];
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
    if (id is! int) return null;

    final titleData = raw['title'];
    if (titleData is! Map<String, dynamic>) return null;

    final title = _text(titleData['english']) ??
        _text(titleData['romaji']) ??
        _text(titleData['native']);
    if (title == null) return null;

    final coverData = raw['coverImage'];
    Uri? poster;
    if (coverData is Map<String, dynamic>) {
      final cover =
          _text(coverData['extraLarge']) ?? _text(coverData['large']);
      if (cover != null) poster = Uri.tryParse(cover);
    }

    final startDate = raw['startDate'];
    String? year;
    if (startDate is Map<String, dynamic>) {
      final value = startDate['year'];
      if (value is int) year = value.toString();
    }

    return MediaItem(
      id: id,
      type: MediaType.anime,
      title: title,
      overview: _description(raw['description']),
      year: year,
      poster: poster,
      backdrop: _uri(raw['bannerImage']),
      episodeCount: raw['episodes'] is int ? raw['episodes'] as int : null,
    );
  }

  String? _description(Object? value) {
    final text = _text(value);
    return text == null ? null : plainTextFromHtml(text);
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
