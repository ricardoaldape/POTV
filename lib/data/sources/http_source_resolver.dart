import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/http_source_config.dart';
import '../../domain/models/stream_candidate.dart';
import '../../domain/services/source_resolver.dart';
import 'http_source_repository.dart';

final httpSourceResolverProvider = Provider<HttpSourceResolver>((ref) {
  return HttpSourceResolver(
    ref.read(httpSourceRepositoryProvider),
    Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 12),
      ),
    ),
  );
});

class HttpSourceResolver implements SourceResolver {
  final HttpSourceRepository _repository;
  final Dio _dio;

  HttpSourceResolver(this._repository, this._dio);

  @override
  Future<List<StreamCandidate>> resolve({
    required String mediaType,
    required String mediaId,
    String? externalId,
    String? title,
    String? year,
    int? season,
    int? episode,
  }) async {
    final sources = await _repository.load();
    final enabled = sources.where((source) => source.enabled).toList();

    final batches = await Future.wait(
      enabled.map(
        (source) => _resolveSource(
          source,
          mediaType: mediaType,
          mediaId: mediaId,
          season: season,
          episode: episode,
        ),
      ),
    );

    return [
      for (final batch in batches) ...batch,
    ];
  }

  Future<List<StreamCandidate>> _resolveSource(
    HttpSourceConfig source, {
    required String mediaType,
    required String mediaId,
    int? season,
    int? episode,
  }) async {
    try {
      final query = <String, String>{
        ...source.endpoint.queryParameters,
        'type': mediaType,
        if (mediaType == 'anime') 'anilist_id': mediaId,
        if (mediaType != 'anime') 'tmdb_id': mediaId,
        if (season != null) 'season': '$season',
        if (episode != null) 'episode': '$episode',
      };
      final uri = source.endpoint.replace(queryParameters: query);

      final response = await _dio.getUri<Object?>(
        uri,
        options: Options(responseType: ResponseType.json),
      );

      return _parseResponse(source, response.data);
    } on DioException {
      return const [];
    } on FormatException {
      return const [];
    }
  }

  List<StreamCandidate> _parseResponse(
    HttpSourceConfig source,
    Object? raw,
  ) {
    Object? streamsRaw;
    if (raw is Map<String, dynamic>) {
      streamsRaw = raw['streams'];
    } else if (raw is List) {
      streamsRaw = raw;
    }

    if (streamsRaw is! List) return const [];

    final result = <StreamCandidate>[];
    for (var index = 0; index < streamsRaw.length; index++) {
      final item = streamsRaw[index];
      if (item is! Map<String, dynamic>) continue;

      final url = Uri.tryParse(item['url']?.toString() ?? '');
      if (url == null ||
          (url.scheme != 'http' && url.scheme != 'https')) {
        continue;
      }

      final name = _text(item['name']) ??
          _text(item['server']) ??
          'Servidor ${index + 1}';
      final backend = _backend(item['backend']);
      final headers = _headers(item['headers']);
      final allowedHosts = _stringSet(item['allowed_hosts']);

      result.add(
        StreamCandidate(
          id: '${source.id}:$index',
          label: '${source.name} · $name',
          uri: url,
          language: _text(item['language']),
          quality: _text(item['quality']),
          backend: backend,
          headers: headers,
          allowedHosts: allowedHosts,
          directWebView: item['direct_webview'] == true,
        ),
      );
    }

    return result;
  }

  PlaybackBackend _backend(Object? value) {
    switch (value?.toString().toLowerCase()) {
      case 'webview':
      case 'web':
        return PlaybackBackend.webView;
      case 'external':
        return PlaybackBackend.external;
      default:
        return PlaybackBackend.native;
    }
  }

  Map<String, String> _headers(Object? value) {
    if (value is! Map) return const {};
    final result = <String, String>{};
    for (final entry in value.entries) {
      final key = entry.key.toString().trim();
      final val = entry.value?.toString().trim();
      if (key.isEmpty || val == null || val.isEmpty) continue;
      result[key] = val;
    }
    return result;
  }

  Set<String> _stringSet(Object? value) {
    if (value is! List) return const {};
    return value
        .map((item) => item?.toString().trim())
        .whereType<String>()
        .where((item) => item.isNotEmpty)
        .toSet();
  }

  String? _text(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
}
