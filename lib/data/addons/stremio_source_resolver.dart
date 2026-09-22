import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/stremio_addon_config.dart';
import '../../domain/models/stream_candidate.dart';
import '../../domain/services/source_resolver.dart';
import 'stremio_addon_repository.dart';

final stremioSourceResolverProvider = Provider<StremioSourceResolver>((ref) {
  return StremioSourceResolver(
    ref.read(stremioAddonRepositoryProvider),
    Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 14),
        headers: const {
          'Accept': 'application/json',
          'User-Agent': 'POTV/0.1 (Android)',
        },
      ),
    ),
  );
});

class StremioSourceResolver implements SourceResolver {
  final StremioAddonRepository _repository;
  final Dio _dio;

  StremioSourceResolver(this._repository, this._dio);

  @override
  Future<List<StreamCandidate>> resolve({
    required String mediaType,
    required String mediaId,
    String? externalId,
    String? title,
    int? season,
    int? episode,
  }) async {
    if (mediaType == 'anime') return const [];

    final resolvedExternalId = externalId ??
        await _findExternalId(
          mediaType: mediaType,
          title: title,
        );

    final itemId = _streamId(
      mediaType: mediaType,
      mediaId: mediaId,
      externalId: resolvedExternalId,
      season: season,
      episode: episode,
    );
    if (itemId == null) return const [];

    final type = mediaType == 'tv' ? 'series' : 'movie';
    final addons = await _repository.load();
    final enabled = addons.where((addon) => addon.enabled).toList();

    final batches = await Future.wait([
      for (final addon in enabled)
        _resolveAddon(
          addon,
          type: type,
          itemId: itemId,
        ),
    ]);

    return [
      for (final batch in batches) ...batch,
    ];
  }

  Future<List<StreamCandidate>> _resolveAddon(
    StremioAddonConfig addon, {
    required String type,
    required String itemId,
  }) async {
    try {
      final encodedId = Uri.encodeComponent(itemId);
      final streamUri = addon.manifestUri.resolve(
        'stream/$type/$encodedId.json',
      );

      final response = await _dio.getUri<Object?>(
        streamUri,
        options: Options(responseType: ResponseType.json),
      );

      final raw = response.data;
      if (raw is! Map<String, dynamic>) return const [];
      final streams = raw['streams'];
      if (streams is! List) return const [];

      final result = <StreamCandidate>[];
      for (var index = 0; index < streams.length; index++) {
        final value = streams[index];
        if (value is! Map<String, dynamic>) continue;

        final url = Uri.tryParse(value['url']?.toString() ?? '');
        if (url == null ||
            (url.scheme != 'http' && url.scheme != 'https')) {
          continue;
        }

        final name = _text(value['name']);
        final streamTitle = _text(value['title']);
        final description = _text(value['description']);
        final label = [
          addon.name,
          name ?? streamTitle ?? description ?? 'Servidor ${index + 1}',
        ].join(' · ');

        result.add(
          StreamCandidate(
            id: 'stremio:${addon.id}:$index',
            label: label,
            uri: url,
            language: _language(value),
            quality: _quality(value),
            headers: _requestHeaders(value['behaviorHints']),
            backend: PlaybackBackend.native,
          ),
        );
      }

      return result;
    } on DioException {
      return const [];
    } on FormatException {
      return const [];
    }
  }

  Future<String?> _findExternalId({
    required String mediaType,
    required String? title,
  }) async {
    if (title == null || title.trim().isEmpty) return null;
    if (mediaType != 'movie' && mediaType != 'tv') return null;

    final resource = mediaType == 'tv' ? 'series' : 'movie';
    final encoded = Uri.encodeComponent(title.trim());
    final uri = Uri.parse(
      'https://v3-cinemeta.strem.io/catalog/$resource/top/search=$encoded.json',
    );

    try {
      final response = await _dio.getUri<Object?>(
        uri,
        options: Options(responseType: ResponseType.json),
      );
      final raw = response.data;
      if (raw is! Map<String, dynamic>) return null;
      final metas = raw['metas'];
      if (metas is! List) return null;

      final target = title.trim().toLowerCase();
      Map<String, dynamic>? first;
      for (final value in metas) {
        if (value is! Map<String, dynamic>) continue;
        first ??= value;
        final name = _text(value['name'])?.toLowerCase();
        if (name == target) {
          return _text(value['imdb_id']) ?? _text(value['id']);
        }
      }

      if (first == null) return null;
      return _text(first['imdb_id']) ?? _text(first['id']);
    } on DioException {
      return null;
    }
  }

  String? _streamId({
    required String mediaType,
    required String mediaId,
    required String? externalId,
    required int? season,
    required int? episode,
  }) {
    final base = externalId?.trim().isNotEmpty == true
        ? externalId!.trim()
        : mediaId.startsWith('tt')
            ? mediaId
            : null;
    if (base == null) return null;

    if (mediaType == 'movie') return base;

    if (mediaType == 'tv') {
      if (season == null || episode == null) return null;
      return '$base:$season:$episode';
    }

    return null;
  }

  Map<String, String> _requestHeaders(Object? behaviorHints) {
    if (behaviorHints is! Map) return const {};
    final proxyHeaders = behaviorHints['proxyHeaders'];
    if (proxyHeaders is! Map) return const {};
    final request = proxyHeaders['request'];
    if (request is! Map) return const {};

    final result = <String, String>{};
    for (final entry in request.entries) {
      final key = entry.key.toString().trim();
      final value = entry.value?.toString().trim();
      if (key.isEmpty || value == null || value.isEmpty) continue;
      result[key] = value;
    }
    return result;
  }

  String? _language(Map<String, dynamic> value) {
    final text = [
      _text(value['name']),
      _text(value['title']),
      _text(value['description']),
    ].whereType<String>().join(' ').toLowerCase();

    if (text.contains('latino') || text.contains('spanish latino')) {
      return 'es-MX';
    }
    if (text.contains('castellano') || text.contains('spanish')) {
      return 'es';
    }
    if (text.contains('english')) return 'en';
    return null;
  }

  String? _quality(Map<String, dynamic> value) {
    final text = [
      _text(value['name']),
      _text(value['title']),
      _text(value['description']),
    ].whereType<String>().join(' ').toLowerCase();

    for (final quality in const ['2160p', '4k', '1080p', '720p', '480p']) {
      if (text.contains(quality)) return quality;
    }
    return null;
  }

  String? _text(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
}
