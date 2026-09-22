import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/stream_candidate.dart';

final animeOfficialStreamingProvider =
    Provider<AnimeOfficialStreamingResolver>((ref) {
  return AnimeOfficialStreamingResolver(
    Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 12),
        headers: const {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'User-Agent': 'POTV/0.1 (Android)',
        },
      ),
    ),
  );
});

class AnimeOfficialStreamingResolver {
  static const _endpoint = 'https://graphql.anilist.co';

  final Dio _dio;
  final Map<int, List<_OfficialEpisode>> _cache = {};

  AnimeOfficialStreamingResolver(this._dio);

  Future<List<StreamCandidate>> resolve({
    required int anilistId,
    required int episode,
  }) async {
    final episodes = await _episodes(anilistId);
    if (episodes.isEmpty) return const [];

    final matching = episodes
        .where((item) => item.episode == episode)
        .toList(growable: false);
    if (matching.isEmpty) return const [];

    return [
      for (var i = 0; i < matching.length; i++)
        StreamCandidate(
          id: 'anilist-official:$anilistId:$episode:$i',
          label: '${matching[i].site} · Episodio $episode',
          uri: matching[i].url,
          backend: PlaybackBackend.external,
        ),
    ];
  }

  Future<List<_OfficialEpisode>> _episodes(int anilistId) async {
    final cached = _cache[anilistId];
    if (cached != null) return cached;

    const query = r'''
      query ($id: Int) {
        Media(id: $id, type: ANIME) {
          streamingEpisodes {
            title
            url
            site
          }
        }
      }
    ''';

    try {
      final response = await _dio.post<Map<String, dynamic>>(
        _endpoint,
        data: {
          'query': query,
          'variables': {'id': anilistId},
        },
      );

      final data = response.data?['data'];
      final media = data is Map ? data['Media'] : null;
      final raw = media is Map ? media['streamingEpisodes'] : null;
      if (raw is! List) return const [];

      final result = <_OfficialEpisode>[];
      for (final value in raw) {
        if (value is! Map) continue;
        final title = value['title']?.toString().trim();
        final site = value['site']?.toString().trim();
        final rawUrl = value['url']?.toString().trim();
        if (title == null ||
            title.isEmpty ||
            site == null ||
            site.isEmpty ||
            rawUrl == null ||
            rawUrl.isEmpty) {
          continue;
        }

        final number = _episodeNumber(title);
        final parsed = Uri.tryParse(rawUrl);
        if (number == null ||
            parsed == null ||
            (parsed.scheme != 'http' && parsed.scheme != 'https')) {
          continue;
        }

        final secureUrl = parsed.scheme == 'http'
            ? parsed.replace(scheme: 'https')
            : parsed;

        result.add(
          _OfficialEpisode(
            episode: number,
            site: site,
            url: secureUrl,
          ),
        );
      }

      _cache[anilistId] = result;
      return result;
    } on DioException {
      return const [];
    }
  }

  int? _episodeNumber(String title) {
    final match = RegExp(
      r'\bEpisode\s+(\d+)\b',
      caseSensitive: false,
    ).firstMatch(title);
    return int.tryParse(match?.group(1) ?? '');
  }
}

class _OfficialEpisode {
  final int episode;
  final String site;
  final Uri url;

  const _OfficialEpisode({
    required this.episode,
    required this.site,
    required this.url,
  });
}
