import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:quickjs_engine/quickjs_engine.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../domain/models/nuvio_plugin_config.dart';
import '../../domain/models/stream_candidate.dart';
import '../../domain/resolution/provider_resolver.dart';

final nuvioPluginRuntimeProvider = Provider<NuvioPluginRuntime>((ref) {
  return NuvioPluginRuntime(Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 15),
    headers: const {'Accept': 'text/javascript,text/plain,*/*'},
  )));
});

class NuvioPluginRuntime {
  final Dio _dio;
  final Map<Uri, String> _scriptCache = {};
  NuvioPluginRuntime(this._dio);

  Future<List<StreamCandidate>> resolve(
    NuvioPluginConfig plugin,
    ProviderResolveRequest request,
  ) async {
    final code = await _loadCode(plugin.scriptUri);
    final runtime = getJavascriptRuntime(xhr: true);
    try {
      final mediaType = request.mediaType == 'anime' ? 'anime' : request.mediaType;
      final call = jsonEncode({
        'tmdbId': request.mediaId,
        'mediaType': mediaType,
        'season': request.season,
        'episode': request.episode,
        'title': request.title,
        'year': request.year,
        'externalId': request.externalId,
      });
      final bootstrap = _bootstrap(
        tmdbApiKey: AppConfig.tmdbApiKey,
        callJson: call,
      );
      final evaluated = await runtime.evaluateAsync(
        '$bootstrap\n$code\n${_invokeScript()}',
        sourceUrl: plugin.scriptUri.toString(),
      ).timeout(const Duration(seconds: 18));
      runtime.executePendingJob();
      if (evaluated.isError) {
        throw StateError(
          'Error JavaScript en ${plugin.name}: ${evaluated.stringResult}',
        );
      }
      final settled = await runtime.handlePromise(evaluated)
          .timeout(const Duration(seconds: 22));
      if (settled.isError) {
        throw StateError(
          'Promise rechazada en ${plugin.name}: ${settled.stringResult}',
        );
      }
      final invocation = _parseInvocation(settled.stringResult);
      if (!invocation.ok) {
        throw StateError(
          'Plugin ${plugin.name}: ${invocation.error ?? 'error sin mensaje'}',
        );
      }
      return parseResults(plugin, jsonEncode(invocation.streams));
    } finally {
      runtime.dispose();
    }
  }

  Future<String> _loadCode(Uri uri) async {
    final cached = _scriptCache[uri];
    if (cached != null) return cached;
    final response = await _dio.getUri<String>(uri, options: Options(responseType: ResponseType.plain));
    final code = response.data ?? '';
    if (code.trim().isEmpty) throw const FormatException('El plugin no contiene código.');
    _scriptCache[uri] = code;
    return code;
  }

  static _NuvioInvocationResult _parseInvocation(String raw) {
    dynamic decoded;
    try {
      decoded = jsonDecode(raw);
      if (decoded is String) decoded = jsonDecode(decoded);
    } catch (error) {
      return _NuvioInvocationResult(
        ok: false,
        streams: const [],
        error: 'Respuesta inválida del runtime: $error',
      );
    }
    if (decoded is! Map) {
      return const _NuvioInvocationResult(
        ok: false,
        streams: [],
        error: 'El runtime no devolvió un objeto de resultado.',
      );
    }
    final map = Map<String, dynamic>.from(decoded);
    final streams = map['streams'];
    return _NuvioInvocationResult(
      ok: map['ok'] == true,
      streams: streams is List ? List<Object?>.from(streams) : const [],
      error: _text(map['error']),
    );
  }

  static List<StreamCandidate> parseResults(
    NuvioPluginConfig plugin,
    String raw,
  ) {
    dynamic decoded;
    try {
      decoded = jsonDecode(raw);
      if (decoded is String) decoded = jsonDecode(decoded);
    } catch (_) {
      return const [];
    }
    if (decoded is! List) return const [];
    final result = <StreamCandidate>[];
    var index = 0;
    for (final value in decoded) {
      if (value is! Map) continue;
      final map = Map<String, dynamic>.from(value);
      final rawUrl = map['url'];
      String? url;
      if (rawUrl is String) {
        url = rawUrl.trim();
      } else if (rawUrl is Map) {
        url = rawUrl['url']?.toString().trim();
      }
      final uri = Uri.tryParse(url ?? '');
      if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) continue;
      final headers = <String, String>{};
      final rawHeaders = map['headers'];
      _mergeHeaders(headers, rawHeaders);
      final behaviorHints = map['behaviorHints'];
      if (behaviorHints is Map) {
        final proxyHeaders = behaviorHints['proxyHeaders'];
        if (proxyHeaders is Map) {
          _mergeHeaders(headers, proxyHeaders['request']);
        }
      }
      final name = _text(map['name']) ?? _text(map['title']) ?? _text(map['provider']) ?? plugin.name;
      result.add(StreamCandidate(
        id: 'nuvio:${plugin.id}:${index++}',
        label: name,
        uri: uri,
        language: _text(map['language']),
        quality: _text(map['quality']),
        backend: PlaybackBackend.native,
        headers: headers,
      ));
    }
    final seen = <String>{};
    return result.where((item) => seen.add(item.uri.toString())).toList(growable: false);
  }

  static void _mergeHeaders(Map<String, String> target, Object? raw) {
    if (raw is! Map) return;
    for (final entry in raw.entries) {
      final key = entry.key.toString().trim();
      final value = entry.value?.toString().trim();
      if (key.isNotEmpty && value != null && value.isNotEmpty) {
        target[key] = value;
      }
    }
  }

  static String? _text(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  String _bootstrap({required String tmdbApiKey, required String callJson}) {
    return '''
var module = { exports: {} };
var exports = module.exports;
var global = globalThis;
var window = globalThis;
var self = globalThis;
var TMDB_API_KEY = ${jsonEncode(tmdbApiKey)};
var __POTV_CALL = ${jsonEncode(callJson)};
var __POTV_META = JSON.parse(__POTV_CALL);
var __POTV_FETCH = typeof globalThis.fetch === 'function' ? globalThis.fetch : null;
if ((!TMDB_API_KEY || String(TMDB_API_KEY).length === 0) && __POTV_FETCH) {
  globalThis.fetch = async function(url, options) {
    var target = String(url || '');
    if (target.indexOf('https://api.themoviedb.org/3/movie/') === 0 ||
        target.indexOf('https://api.themoviedb.org/3/tv/') === 0) {
      var title = __POTV_META.title || '';
      var year = String(__POTV_META.year || '').match(/[0-9]{4}/);
      var date = year ? year[0] + '-01-01' : '';
      var payload = {
        id: parseInt(__POTV_META.tmdbId || '0', 10) || 0,
        title: title,
        name: title,
        original_title: title,
        original_name: title,
        release_date: date,
        first_air_date: date,
        imdb_id: __POTV_META.externalId || null
      };
      return {
        ok: title.length > 0,
        status: title.length > 0 ? 200 : 404,
        statusText: title.length > 0 ? 'OK' : 'Not Found',
        url: target,
        headers: { get: function() { return null; } },
        text: function() { return Promise.resolve(JSON.stringify(payload)); },
        json: function() { return Promise.resolve(payload); }
      };
    }
    return __POTV_FETCH(url, options);
  };
}
if (typeof atob === 'undefined') {
  globalThis.atob = function(input) {
    var chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';
    var str = String(input).replace(/=+\$/, '');
    var output = '', bc = 0, bs, buffer, idx = 0;
    if (str.length % 4 === 1) throw new Error('Invalid base64');
    while ((buffer = str.charAt(idx++))) {
      buffer = chars.indexOf(buffer);
      if (buffer === -1) continue;
      bs = bc % 4 ? bs * 64 + buffer : buffer;
      if (bc++ % 4) output += String.fromCharCode(255 & (bs >> ((-2 * bc) & 6)));
    }
    return output;
  };
}
if (typeof require === 'undefined') {
  globalThis.require = function(name) {
    throw new Error('Unsupported module in POTV runtime: ' + name);
  };
}
''';
  }

  String _invokeScript() => '''
(async function() {
  try {
    var fn = (module.exports && module.exports.getStreams) || globalThis.getStreams;
    if (typeof fn !== 'function') {
      return JSON.stringify({ ok: false, streams: [], error: 'getStreams no está exportado por el plugin.' });
    }
    var args = JSON.parse(__POTV_CALL);
    var value = await fn(args.tmdbId, args.mediaType, args.season == null ? undefined : args.season, args.episode == null ? undefined : args.episode);
    return JSON.stringify({ ok: true, streams: Array.isArray(value) ? value : [] });
  } catch (e) {
    var message = e && e.stack ? String(e.stack) : (e && e.message ? String(e.message) : String(e));
    return JSON.stringify({ ok: false, streams: [], error: message });
  }
})();
''';
}

class _NuvioInvocationResult {
  final bool ok;
  final List<Object?> streams;
  final String? error;

  const _NuvioInvocationResult({
    required this.ok,
    required this.streams,
    this.error,
  });
}
