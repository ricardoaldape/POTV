import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/media_item.dart';
import '../../domain/models/series_episode.dart';

final seriesEpisodeRepositoryProvider = Provider<SeriesEpisodeRepository>((ref) {
  return SeriesEpisodeRepository(Dio());
});

final seriesEpisodesProvider =
    FutureProvider.autoDispose.family<List<SeriesEpisode>, MediaItem>((ref, item) {
  return ref.read(seriesEpisodeRepositoryProvider).load(item);
});

class SeriesEpisodeRepository {
  static const _base = 'https://v3-cinemeta.strem.io';

  final Dio _dio;

  SeriesEpisodeRepository(this._dio);

  Future<List<SeriesEpisode>> load(MediaItem item) async {
    if (item.type != MediaType.tv) return const [];

    var imdbId = item.externalId;
    if (imdbId == null || !imdbId.startsWith('tt')) {
      imdbId = await _findImdbId(item.title);
    }
    if (imdbId == null) return const [];

    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '$_base/meta/series/$imdbId.json',
        options: Options(
          headers: const {
            'Accept': 'application/json',
            'User-Agent': 'Mozilla/5.0 POTV/0.1',
          },
        ),
      );

      final meta = response.data?['meta'];
      if (meta is! Map<String, dynamic>) return const [];
      final videos = meta['videos'];
      if (videos is! List) return const [];

      final episodes = <SeriesEpisode>[];
      for (final value in videos) {
        if (value is! Map<String, dynamic>) continue;
        final season = _int(value['season']);
        final episode = _int(value['episode']);
        if (season == null || episode == null || season < 1 || episode < 1) {
          continue;
        }

        episodes.add(
          SeriesEpisode(
            season: season,
            episode: episode,
            title: _text(value['name']) ?? 'Episodio $episode',
            overview: _text(value['overview']),
            thumbnail: _uri(value['thumbnail']),
            releasedAt: DateTime.tryParse(_text(value['released']) ?? ''),
          ),
        );
      }

      episodes.sort((a, b) {
        final bySeason = a.season.compareTo(b.season);
        if (bySeason != 0) return bySeason;
        return a.episode.compareTo(b.episode);
      });
      return episodes;
    } on DioException {
      return const [];
    }
  }

  Future<String?> _findImdbId(String title) async {
    final encoded = Uri.encodeComponent(title.trim());
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '$_base/catalog/series/top/search=$encoded.json',
        options: Options(
          headers: const {
            'Accept': 'application/json',
            'User-Agent': 'Mozilla/5.0 POTV/0.1',
          },
        ),
      );
      final metas = response.data?['metas'];
      if (metas is! List) return null;

      final target = title.trim().toLowerCase();
      for (final value in metas) {
        if (value is! Map<String, dynamic>) continue;
        final name = _text(value['name'])?.toLowerCase();
        if (name == target) {
          return _text(value['imdb_id']) ?? _text(value['id']);
        }
      }

      if (metas.isNotEmpty && metas.first is Map<String, dynamic>) {
        final first = metas.first as Map<String, dynamic>;
        return _text(first['imdb_id']) ?? _text(first['id']);
      }
      return null;
    } on DioException {
      return null;
    }
  }

  int? _int(Object? value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
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
