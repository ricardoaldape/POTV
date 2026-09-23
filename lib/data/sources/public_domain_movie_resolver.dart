import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/stream_candidate.dart';

final publicDomainMovieResolverProvider =
    Provider<PublicDomainMovieResolver>((ref) {
  return PublicDomainMovieResolver(
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

class PublicDomainMovieResolver {
  static const _searchEndpoint =
      'https://archive.org/advancedsearch.php';
  static const _metadataBase = 'https://archive.org/metadata/';

  final Dio _dio;

  PublicDomainMovieResolver(this._dio);

  Future<List<StreamCandidate>> resolve({
    required String mediaType,
    required String? title,
    required String? year,
  }) async {
    if (mediaType != 'movie') return const [];
    final cleanTitle = title?.trim();
    if (cleanTitle == null || cleanTitle.isEmpty) return const [];

    final candidates = await _search(cleanTitle, year);
    if (candidates.isEmpty) return const [];

    for (final item in candidates.take(4)) {
      final streams = await _streamsFor(item, requestedTitle: cleanTitle, requestedYear: year);
      if (streams.isNotEmpty) return streams;
    }

    return const [];
  }

  Future<List<_ArchiveItem>> _search(
    String title,
    String? year,
  ) async {
    final escapedTitle = title.replaceAll('"', r'\"');
    final yearValue = int.tryParse(year ?? '');

    final query = [
      'title:("$escapedTitle")',
      'mediatype:(movies)',
      'licenseurl:(*publicdomain*)',
      if (yearValue != null) 'year:($yearValue)',
    ].join(' AND ');

    try {
      final response = await _dio.get<Map<String, dynamic>>(
        _searchEndpoint,
        queryParameters: {
          'q': query,
          'fl[]': [
            'identifier',
            'title',
            'year',
            'licenseurl',
          ],
          'rows': 12,
          'page': 1,
          'output': 'json',
          'sort[]': ['downloads desc'],
        },
      );

      final payload = response.data?['response'];
      final docs = payload is Map ? payload['docs'] : null;
      if (docs is! List) return const [];

      final target = _normalize(title);
      final result = <_ArchiveItem>[];

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

        final normalizedResult = _normalize(
          resultTitle.replaceAll(
            RegExp(r'\s*\(\s*\d{4}\s*\)\s*'),
            ' ',
          ),
        );

        final exact = normalizedResult == target;
        final startsWith = normalizedResult.startsWith('$target ');
        if (!exact && !startsWith) continue;

        result.add(
          _ArchiveItem(
            identifier: identifier,
            title: resultTitle,
            year: int.tryParse(value['year']?.toString() ?? ''),
            licenseUrl: license,
          ),
        );
      }

      result.sort((a, b) {
        final aExact = _normalize(a.title) == target ? 1 : 0;
        final bExact = _normalize(b.title) == target ? 1 : 0;
        if (aExact != bExact) return bExact.compareTo(aExact);

        if (yearValue != null) {
          final aYear = a.year == yearValue ? 1 : 0;
          final bYear = b.year == yearValue ? 1 : 0;
          if (aYear != bYear) return bYear.compareTo(aYear);
        }

        return 0;
      });

      return result;
    } on DioException {
      return const [];
    }
  }

  Future<List<StreamCandidate>> _streamsFor(
    _ArchiveItem item, {
    required String requestedTitle,
    required String? requestedYear,
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

      final metadataTitle = _text(metadata['title']);
      if (metadataTitle == null || _normalize(metadataTitle) != _normalize(requestedTitle)) {
        return const [];
      }
      final expectedYear = int.tryParse(requestedYear ?? '');
      if (expectedYear != null) {
        final metadataYear = int.tryParse(metadata['year']?.toString() ?? '');
        if (metadataYear != expectedYear) return const [];
      }

      final files = raw['files'];
      if (files is! List) return const [];

      final videoFiles = <_ArchiveVideo>[];
      for (final value in files) {
        if (value is! Map) continue;
        final name = _text(value['name']);
        if (name == null || !_isPlayableVideo(name)) continue;

        final format = _text(value['format']) ?? '';
        final size = int.tryParse(value['size']?.toString() ?? '') ?? 0;
        final height = int.tryParse(value['height']?.toString() ?? '');

        if (!_isDirectVideoFormat(format, name)) continue;

        videoFiles.add(
          _ArchiveVideo(
            name: name,
            size: size,
            height: height,
          ),
        );
      }

      if (videoFiles.isEmpty) return const [];

      videoFiles.sort((a, b) => _score(b).compareTo(_score(a)));

      final result = <StreamCandidate>[];
      for (var i = 0; i < math.min(videoFiles.length, 4); i++) {
        final file = videoFiles[i];
        final uri = Uri.parse(
          'https://archive.org/download/'
          '${Uri.encodeComponent(item.identifier)}/'
          '${Uri.encodeComponent(file.name)}',
        );

        result.add(
          StreamCandidate(
            id: 'archive:${item.identifier}:$i',
            label: 'Internet Archive · Dominio público',
            uri: uri,
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

  int _score(_ArchiveVideo value) {
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

    if (value.size > 0 && value.size < 2 * 1024 * 1024 * 1024) {
      score += 8;
    }
    if (value.size > 0 && value.size < 800 * 1024 * 1024) {
      score += 4;
    }

    return score;
  }

  String _normalize(String value) {
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
    out = out.replaceAll(RegExp(r'[^a-z0-9]+'), ' ');
    return out.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  String? _text(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
}

class _ArchiveItem {
  final String identifier;
  final String title;
  final int? year;
  final String licenseUrl;

  const _ArchiveItem({
    required this.identifier,
    required this.title,
    required this.year,
    required this.licenseUrl,
  });
}

class _ArchiveVideo {
  final String name;
  final int size;
  final int? height;

  const _ArchiveVideo({
    required this.name,
    required this.size,
    required this.height,
  });
}
