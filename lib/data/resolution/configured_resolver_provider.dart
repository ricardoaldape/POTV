import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../domain/models/stream_candidate.dart';
import '../../domain/resolution/provider_resolver.dart';
import '../../domain/resolution/resolver_endpoint_config.dart';
import '../debug/debug_log_provider.dart';

class ConfiguredResolverProvider extends ProviderResolver {
  final ResolverEndpointConfig config;
  final Dio dio;

  ConfiguredResolverProvider(
    this.config, {
    Dio? dio,
  }) : dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 8),
                receiveTimeout: const Duration(seconds: 14),
                headers: const {
                  'Accept': 'application/json',
                  'User-Agent': 'POTV/0.6 (Android)',
                },
              ),
            );

  @override
  String get id => config.id;

  @override
  String get displayName => config.name;

  @override
  int get priority => config.priority;

  @override
  Set<String> get supportedMediaTypes => config.mediaTypes;

  @override
  Future<List<StreamCandidate>> resolve(ProviderResolveRequest request) async {
    final query = <String, String>{
      ...config.endpoint.queryParameters,
      'type': request.mediaType,
      if (request.isAnime) 'anilist_id': request.mediaId,
      if (!request.isAnime) 'tmdb_id': request.mediaId,
      if (request.externalId?.trim().isNotEmpty == true)
        'external_id': request.externalId!.trim(),
      if (request.title?.trim().isNotEmpty == true)
        'title': request.title!.trim(),
      if (request.year?.trim().isNotEmpty == true) 'year': request.year!.trim(),
      if (request.season != null) 'season': '${request.season}',
      if (request.episode != null) 'episode': '${request.episode}',
    };

    try {
      final uri = config.endpoint.replace(queryParameters: query);
      _log('Resolver ${config.name} GET -> $uri');
      final response = await dio.getUri<Object?>(
        uri,
        options: Options(responseType: ResponseType.json),
      );
      final candidates = _parse(response.data);
      _log('Resolver ${config.name}: ${candidates.length} URLs.');
      for (var index = 0; index < candidates.length; index++) {
        _log(
          'Resolver ${config.name} URL ${index + 1}/${candidates.length} '
          '-> ${candidates[index].uri}',
        );
      }
      return candidates;
    } catch (error, stackTrace) {
      _logError('Resolver ${config.name}', error, stackTrace);
      return const [];
    }
  }
  void _log(String message) {
    debugPrint(message);
    addDebugLog(message);
  }

  void _logError(String scope, Object error, StackTrace stackTrace) {
    final errorLog = '$scope ERROR ${error.runtimeType}: $error';
    final stackLog = '$scope STACK: $stackTrace';
    debugPrint(errorLog);
    debugPrint(stackLog);
    addDebugLog(errorLog);
    addDebugLog(stackLog);
  }

  List<StreamCandidate> _parse(Object? raw) {
    Object? streamsRaw;
    if (raw is Map<String, dynamic>) {
      streamsRaw = raw['streams'] ?? raw['results'] ?? raw['servidores'];
    } else if (raw is List) {
      streamsRaw = raw;
    }
    if (streamsRaw is! List) return const [];

    final result = <StreamCandidate>[];
    for (var index = 0; index < streamsRaw.length; index++) {
      final value = streamsRaw[index];
      if (value is! Map) continue;

      final item = value.map(
        (key, value) => MapEntry(key.toString(), value),
      );
      final uri = Uri.tryParse(
        item['url']?.toString() ??
            item['stream_url']?.toString() ??
            item['servidor_url']?.toString() ??
            item['resolved_m3u8']?.toString() ??
            item['uri']?.toString() ??
            '',
      );
      if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
        continue;
      }

      result.add(
        StreamCandidate(
          id: '${config.id}:$index',
          label: '${config.name} · ${_name(item, index)}',
          uri: uri,
          language: _text(item['language']) ?? _text(item['idioma']),
          quality: _text(item['quality']) ?? _text(item['calidad']),
          backend: _backend(item, uri),
          headers: _headers(item['headers']),
          allowedHosts:
              _stringSet(item['allowed_hosts'] ?? item['allowedHosts']),
          directWebView:
              item['direct_webview'] == true || item['directWebView'] == true,
        ),
      );
    }
    return result;
  }

  String _name(Map<String, dynamic> item, int index) {
    return _text(item['name']) ??
        _text(item['server']) ??
        _text(item['servidor_nombre']) ??
        'Servidor ${index + 1}';
  }

  PlaybackBackend _backend(Map<String, dynamic> item, Uri uri) {
    final explicit = item['backend']?.toString().trim().toLowerCase();
    switch (explicit) {
      case 'native':
        return PlaybackBackend.native;
      case 'webview':
      case 'web':
        return PlaybackBackend.webView;
      case 'external':
        return PlaybackBackend.external;
    }

    if (_text(item['resolved_m3u8']) != null ||
        _text(item['stream_url']) != null ||
        _looksLikeDirectMedia(uri)) {
      return PlaybackBackend.native;
    }

    return PlaybackBackend.webView;
  }

  bool _looksLikeDirectMedia(Uri uri) {
    final value = uri.toString().toLowerCase();
    return value.contains('.m3u8') ||
        value.contains('.mp4') ||
        value.contains('.m4v') ||
        value.contains('.webm') ||
        value.contains('manifest');
  }
  Map<String, String> _headers(Object? value) {
    if (value is! Map) return const {};
    final result = <String, String>{};
    for (final entry in value.entries) {
      final key = entry.key.toString().trim();
      final item = entry.value?.toString().trim();
      if (key.isEmpty || item == null || item.isEmpty) continue;
      result[key] = item;
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
