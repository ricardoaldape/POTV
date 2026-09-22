import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/stream_candidate.dart';

final publicDomainSeriesResolverProvider =
    Provider<PublicDomainSeriesResolver>((ref) {
  return PublicDomainSeriesResolver(
    Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 16),
        headers: const {
          'Accept': 'application/json',
          'User-Agent': 'POTV/0.1 (Android)',
        },
      ),
    ),
  );
});

class PublicDomainSeriesResolver {
  static const _searchEndpoint =
      'https://archive.org/advancedsearch.php';
  static const _metadataBase = 'https://archive.org/metadata/';

  final Dio _dio;

  PublicDomainSeriesResolver(this._dio);

  Future<List<StreamCandidate>> resolve({
    required String mediaType,
    required String? title,
    required int? season,
    required int? episode,
  }) async {
    if (mediaType != 'tv' ||
        season == null ||
        episode == null ||
        season < 1 ||
        episode < 1) {
      return const [];
    }

    final cleanTitle = title?.trim();
    if (cleanTitle == null || cleanTitle.isEmpty) return const [];

    final items = await _search(cleanTitle, season, episode);
    if (items.isEmpty) return const [];

    final result = <StreamCandidate>[];
    for (final item in items.take(4)) {
      result.addAll(
        await _streamsFor(
          item,
          season: season,
          episode: episode,
        ),
      );
      if (result.length >= 4) break;
    }

    return result.take(4).toList(growable: false);
  }

  Future<List<_ArchiveSeriesItem>> _search(
    String title,
    int season,
    int episode,
  ) async {
    final escapedTitle = title.replaceAll('"', r'\"');
    final query = [
      'title:("$escapedTitle")',
      'mediatype:(movies)',
      'licenseurl:(*publicdomain*)',
    ].join(' AND ');

    try {
      final response = await _dio.get<Map<String, dynamic>>(
        _searchEndpoint,
        queryParameters: {
          'q': query,
          'fl[]': [
            'identifier',
            'title',
            'licenseurl',
          ],
          'rows': 50,
          'page': 1,
          'output': 'json',
          'sort[]': ['downloads desc'],
        },
      );

      final payload = response.data?['response'];
      final docs = payload is Map ? payload['docs'] : null;
      if (docs is! List) return const [];

      final seriesKey = _compact(title);
      final result = <_ArchiveSeriesItem>[];

      for (final value in docs) {
        if (value is! Map) continue;
        final identifier = _text(value['identifier']);
        final resultTitle = _text(value['title']);
        final license = _text(value['licenseurl']);
        if (identifier == null ||
            resultTitle == null ||
            license == null ||
            !_isPublicDomainLicense(license)) {
          continue;
        }

        final combined = _compact('$resultTitle $identifier');
        if (!combined.contains(seriesKey)) continue;
        if (!_matchesEpisode(combined, season, episode)) continue;

        result.add(
          _ArchiveSeriesItem(
            identifier: identifier,
            title: resultTitle,
            licenseUrl: license,
          ),
        );
      }

      return result;
    } on DioException {
      return const [];
    }
  }

  bool _matchesEpisode(
    String compact,
    int season,
    int episode,
  ) {
    final s2 = season.toString().padLeft(2, '0');
    final e2 = episode.toString().padLeft(2, '0');

    final markers = <String>{
      's${s2}e$e2',
      's${season}e$episode',
      '${season}x$e2',
      '${season}x$episode',
      'ep${season}x$e2',
      'ep${season}x$episode',
    };

    if (season == 1) {
      markers.addAll({
        'ep$e2',
        'episode$e2',
        'episode$episode',
      });
    }

    return markers.any(compact.contains);
  }

  Future<List<StreamCandidate>> _streamsFor(
    _ArchiveSeriesItem item, {
    required int season,
    required int episode,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '$_metadataBase${Uri.encodeComponent(item.identifier)}',
      );

      final raw = response.data;
      if (raw == null) return const [];

      final metadata = raw['metadata'];
      if (metadata is! Map) return const [];
      final license = _text(metadata['licenseurl']) ?? item.licenseUrl;
      if (!_isPublicDomainLicense(license)) return const [];

      final files = raw['files'];
      if (files is! List) return const [];

      final videos = <_ArchiveSeriesVideo>[];
      for (final value in files) {
        if (value is! Map) continue;
        final name = _text(value['name']);
        if (name == null || !_isPlayableVideo(name)) continue;

        final format = _text(value['format']) ?? '';
        if (!_isDirectVideoFormat(format, name)) continue;

        videos.add(
          _ArchiveSeriesVideo(
            name: name,
            size: int.tryParse(value['size']?.toString() ?? '') ?? 0,
            height: int.tryParse(value['height']?.toString() ?? ''),
          ),
        );
      }

      if (videos.isEmpty) return const [];
      videos.sort((a, b) => _score(b).compareTo(_score(a)));

      final result = <StreamCandidate>[];
      for (var i = 0; i < math.min(videos.length, 3); i++) {
        final file = videos[i];
        result.add(
          StreamCandidate(
            id: 'archive-series:${item.identifier}:$i',
            label:
                'Internet Archive · Dominio público · T$season E$episode',
            uri: Uri.parse(
              'https://archive.org/download/'
              '${Uri.encodeComponent(item.identifier)}/'
              '${Uri.encodeComponent(file.name)}',
            ),
            quality: file.height == null ? null : '${file.height}p',
            backend: PlaybackBackend.native,
          ),
        );
      }
      return result;
    } on DioException {
      return const [];
    }
  }

  bool _isPublicDomainLicense(String value) {
    final normalized = value.toLowerCase();
    return normalized.contains('creativecommons.org/publicdomain/') ||
        normalized.contains('creativecommons.org/licenses/publicdomain/');
  }

  bool _isPlayableVideo(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith('.mp4') ||
        lower.endsWith('.m4v') ||
        lower.endsWith('.webm');
  }

  bool _isDirectVideoFormat(String format, String name) {
    final lowerFormat = format.toLowerCase();
    final lowerName = name.toLowerCase();
    return lowerFormat.contains('mpeg4') ||
        lowerFormat.contains('h.264') ||
        lowerFormat.contains('webm') ||
        lowerName.endsWith('.mp4') ||
        lowerName.endsWith('.m4v') ||
        lowerName.endsWith('.webm');
  }

  int _score(_ArchiveSeriesVideo value) {
    var score = 0;
    final height = value.height ?? 0;
    if (height >= 1080) {
      score += 30;
    } else if (height >= 720) {
      score += 24;
    } else if (height >= 480) {
      score += 18;
    } else if (height > 0) {
      score += 10;
    }

    if (value.name.toLowerCase().endsWith('.mp4')) score += 20;
    if (value.size > 0 && value.size < 1200 * 1024 * 1024) score += 8;
    if (value.size > 0 && value.size < 500 * 1024 * 1024) score += 4;
    return score;
  }

  String _compact(String value) {
    var out = value.toLowerCase();
    const replacements = <String, String>{
      'á': 'a',
      'é': 'e',
      'í': 'i',
      'ó': 'o',
      'ú': 'u',
      'ü': 'u',
      'ñ': 'n',
    };
    for (final entry in replacements.entries) {
      out = out.replaceAll(entry.key, entry.value);
    }
    return out.replaceAll(RegExp(r'[^a-z0-9]+'), '');
  }

  String? _text(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
}

class _ArchiveSeriesItem {
  final String identifier;
  final String title;
  final String licenseUrl;

  const _ArchiveSeriesItem({
    required this.identifier,
    required this.title,
    required this.licenseUrl,
  });
}

class _ArchiveSeriesVideo {
  final String name;
  final int size;
  final int? height;

  const _ArchiveSeriesVideo({
    required this.name,
    required this.size,
    required this.height,
  });
}
