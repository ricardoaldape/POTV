import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/security/media_url_logging.dart';
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
      _log('Resolver ${config.name} GET -> ${safeMediaUrlForLog(uri)}');
      final response = await dio.getUri<Object?>(
        uri,
        options: Options(responseType: ResponseType.json),
      );
      final candidates = parseResponse(response.data);
      _log('Resolver ${config.name}: ${candidates.length} URLs.');
      for (var index = 0; index < candidates.length; index++) {
        _log(
          'Resolver ${config.name} URL ${index + 1}/${candidates.length} '
          '-> ${safeMediaUrlForLog(candidates[index].uri)}',
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

  /// Supports a partner's live server directory with multiple alternatives,
  /// including signed URLs that have no file extension. Server 1 / 2 / N
  /// always reflects the actual displayed source rather than a name match.
  List<StreamCandidate> parseResponse(Object? raw) {
    Object? streamsRaw = raw;
    if (raw is Map) {
      final data = raw['data'] is Map ? raw['data'] as Map : raw;
      streamsRaw = data['streams'] ??
          data['sources'] ??
          data['servers'] ??
          data['results'] ??
          data['servidores'];
    }
    if (streamsRaw is! List) return const [];

    final result = <StreamCandidate>[];
    for (var index = 0; index < streamsRaw.length; index++) {
      final value = streamsRaw[index];
      if (value is! Map) continue;
      final item = value.map(
        (key, value) => MapEntry(key.toString(), value),
      );
      final status = _text(item['status'])?.toLowerCase();
      if (item['enabled'] == false ||
          status == 'disabled' ||
          status == 'offline') {
        continue;
      }

      // A gateway can send either a single stream or a stream + backups.
      // Each backup is independently selectable and can be the next fallback.
      final sources = <Map<String, dynamic>>[item];
      final backups = item['backup_urls'] ??
          item['backups'] ??
          item['mirrors'] ??
          item['alternatives'];
      if (backups is List) {
        for (final entry in backups) {
          if (entry is String) {
            sources.add({...item, 'stream_url': entry, 'url': entry});
          } else if (entry is Map) {
            sources.add({
              ...item,
              ...entry.map((key, value) => MapEntry(key.toString(), value)),
            });
          }
        }
      }
      final inner = item['sources'];
      if (inner is List && inner.isNotEmpty) {
        sources.clear();
        for (final source in inner) {
          if (source is Map) {
            sources.add({
              ...item,
              ...source.map((key, value) => MapEntry(key.toString(), value)),
            });
          }
        }
      }

      for (var alternate = 0; alternate < sources.length; alternate++) {
        final source = sources[alternate];
        final url = _text(source['real_url']) ??
            _text(source['realUrl']) ??
            _text(source['stream_url']) ??
            _text(source['streamUrl']) ??
            _text(source['playback_url']) ??
            _text(source['resolved_m3u8']) ??
            _text(source['servidor_url']) ??
            _text(source['embed_url']) ??
            _text(source['embedUrl']) ??
            _text(source['origin_url']) ??
            _text(source['originUrl']) ??
            _text(source['url']) ??
            _text(source['uri']);
        final uri = Uri.tryParse(url ?? '');
        if (uri == null || uri.host.isEmpty ||
            (uri.scheme != 'https' && uri.scheme != 'http') ||
            uri.userInfo.isNotEmpty) {
          continue;
        }
        final name = _name(source, index);
        final label = alternate == 0
            ? 'Servidor ${index + 1} · $name'
            : 'Servidor ${index + 1} · $name (respaldo $alternate)';
        final backend = _backend(source, uri);
        final language =
            _text(source['language']) ?? _text(source['idioma']);
        final quality = _text(source['quality']) ?? _text(source['calidad']);
        final headers = _headers(source['headers']);
        final allowedHosts =
            _stringSet(source['allowed_hosts'] ?? source['allowedHosts']);
        result.add(StreamCandidate(
          id: '${config.id}:${index + 1}:$alternate',
          label: label,
          uri: uri,
          language: language,
          quality: quality,
          backend: backend,
          headers: headers,
          allowedHosts: allowedHosts,
          directWebView: source['direct_webview'] == true ||
              source['directWebView'] == true,
        ));

        // Use a provider's native media and keep its distinct HTML embed as
        // an optional fallback; never scrape cross-origin iframe contents.
        final embedText =
            _text(source['embed_url']) ?? _text(source['embedUrl']);
        final embedUri = Uri.tryParse(embedText ?? '');
        if (backend == PlaybackBackend.native &&
            embedUri != null &&
            embedUri != uri &&
            (embedUri.scheme == 'https' || embedUri.scheme == 'http') &&
            embedUri.host.isNotEmpty &&
            embedUri.userInfo.isEmpty) {
          result.add(StreamCandidate(
            id: '${config.id}:${index + 1}:$alternate:embed',
            label: '$label (alternativa web)',
            uri: embedUri,
            language: language,
            quality: quality,
            backend: PlaybackBackend.webView,
            // Do not forward CDN authorization headers to another HTML host.
            headers: const {},
            allowedHosts: allowedHosts,
            directWebView: true,
          ));
        }
      }
    }
    return result;
  }

  String _name(Map<String, dynamic> item, int index) {
    return _text(item['name']) ??
        _text(item['provider']) ??
        _text(item['host']) ??
        _text(item['server']) ??
        _text(item['servidor_nombre']) ??
        'Servidor ${index + 1}';
  }

  PlaybackBackend _backend(Map<String, dynamic> item, Uri uri) {
    final explicit = item['backend']?.toString().trim().toLowerCase();
    if (explicit == 'external') return PlaybackBackend.external;

    final embedUrl = _text(item['embed_url']) ?? _text(item['embedUrl']);
    // Classify the selected URI, not an unrelated HTML fallback.
    if (embedUrl != null && Uri.tryParse(embedUrl) == uri) {
      return PlaybackBackend.webView;
    }

    final contentType = (_text(item['content_type']) ??
            _text(item['mime_type']) ??
            _text(item['mimeType']) ??
            '')
        .toLowerCase();
    final typedMedia = contentType.startsWith('video/') ||
        contentType.startsWith('audio/') ||
        contentType.contains('mpegurl') ||
        contentType.contains('dash+xml');
    final declaredStream = [
      'real_url',
      'realUrl',
      'stream_url',
      'streamUrl',
      'playback_url',
      'resolved_m3u8',
    ].any((key) => Uri.tryParse(_text(item[key]) ?? '') == uri);

    // Keep authorized HLS/DASH/MP4 even when the provider also sends
    // metadata describing its HTML player or an extensionless CDN URL.
    final nativeEvidence = _looksLikeDirectMedia(uri) ||
        typedMedia ||
        (_text(item['resolved_m3u8']) != null &&
            Uri.tryParse(_text(item['resolved_m3u8'])!) == uri);
    if (nativeEvidence &&
        (declaredStream ||
            explicit == 'native' ||
            embedUrl == null ||
            (embedUrl != uri.toString() && _looksLikeDirectMedia(uri)))) {
      return PlaybackBackend.native;
    }
    if (item['requires_extraction'] == true ||
        item['requiresExtraction'] == true ||
        item['is_iframe'] == true) {
      return PlaybackBackend.webView;
    }
    switch (explicit) {
      case 'native':
        return PlaybackBackend.native;
      case 'webview':
      case 'web':
        return PlaybackBackend.webView;
    }
    if (embedUrl != null) return PlaybackBackend.webView;
    return nativeEvidence ? PlaybackBackend.native : PlaybackBackend.webView;
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
