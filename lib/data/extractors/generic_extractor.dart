import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;

import '../../config/extractors_config.dart';
import '../../domain/models/stream_candidate.dart';

class GenericExtractor {
  final ExtractorConfig config;
  final Dio _dio;

  GenericExtractor(
    this.config, {
    Dio? dio,
  }) : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 15),
                responseType: ResponseType.plain,
              ),
            );

  Future<List<StreamCandidate>> extract(String url) async {
    final source = _httpUri(url);
    if (source == null || !config.matches(source)) return const [];

    try {
      final extraction = switch (config.type) {
        ExtractorType.regexDirect => _extractRegexDirect(source),
        ExtractorType.regexFromScript => _extractRegexFromScript(source),
        ExtractorType.iframeFollow => _extractIframeFollow(source),
        ExtractorType.base64Decode => _extractBase64(source),
        ExtractorType.customHeaders => _extractRegexDirect(source),
      };
      return await extraction;
    } on DioException {
      return const [];
    } on FormatException {
      return const [];
    } on StateError {
      return const [];
    }
  }

  Future<List<StreamCandidate>> _extractRegexDirect(Uri source) async {
    final body = await _fetch(source);
    return _buildCandidates(
      _regexValues(body),
      baseUri: source,
    );
  }

  Future<List<StreamCandidate>> _extractRegexFromScript(Uri source) async {
    final body = await _fetch(source);
    final document = html_parser.parse(body);
    final values = <String>[];

    for (final script in document.querySelectorAll('script')) {
      values.addAll(_regexValues(script.text));
    }

    return _buildCandidates(values, baseUri: source);
  }

  Future<List<StreamCandidate>> _extractIframeFollow(Uri source) async {
    final body = await _fetch(source);
    final document = html_parser.parse(body);
    final result = <StreamCandidate>[];
    final seen = <String>{};

    for (final iframe in document.querySelectorAll('iframe')) {
      final rawSrc =
          iframe.attributes['src'] ?? iframe.attributes['data-src'] ?? '';
      final iframeUri = _resolveUri(rawSrc, source);
      if (iframeUri == null) continue;

      final iframeBody = await _fetch(
        iframeUri,
        referer: source.toString(),
      );
      final candidates = _buildCandidates(
        _regexValues(iframeBody),
        baseUri: iframeUri,
      );

      for (final candidate in candidates) {
        if (seen.add(candidate.uri.toString())) {
          result.add(candidate);
        }
      }
    }

    return result;
  }

  Future<List<StreamCandidate>> _extractBase64(Uri source) async {
    final body = await _fetch(source);
    final decodedValues = <String>[];

    for (final encoded in _regexValues(body)) {
      final payload = _stripDataUri(encoded);
      if (payload.isEmpty) continue;

      try {
        final bytes = base64.decode(base64.normalize(payload));
        final decoded = utf8.decode(bytes, allowMalformed: true).trim();
        if (decoded.isEmpty) continue;

        final direct = _resolveUri(decoded, source);
        if (direct != null) {
          decodedValues.add(direct.toString());
          continue;
        }

        decodedValues.addAll(_genericUrls(decoded));
      } on FormatException {
        continue;
      }
    }

    return _buildCandidates(decodedValues, baseUri: source);
  }

  Future<String> _fetch(
    Uri uri, {
    String? referer,
  }) async {
    final headers = <String, String>{
      ...?config.headers,
    };

    if (referer != null && !_containsHeader(headers, 'referer')) {
      headers['Referer'] = referer;
    }

    final response = await _dio.getUri<Object?>(
      uri,
      options: Options(
        headers: headers.isEmpty ? null : headers,
        responseType: ResponseType.plain,
        followRedirects: true,
      ),
    );

    return response.data?.toString() ?? '';
  }

  List<String> _regexValues(String input) {
    final pattern = config.pattern.trim();
    if (pattern.isEmpty || input.isEmpty) return const [];

    final expression = RegExp(
      pattern,
      caseSensitive: false,
      multiLine: true,
      dotAll: true,
    );

    final values = <String>[];
    for (final match in expression.allMatches(input)) {
      final value = _firstCapturedValue(match);
      if (value != null && value.trim().isNotEmpty) {
        values.add(value.trim());
      }
    }
    return values;
  }

  String? _firstCapturedValue(RegExpMatch match) {
    for (var group = 1; group <= match.groupCount; group++) {
      final value = match.group(group);
      if (value != null && value.isNotEmpty) return value;
    }
    return match.group(0);
  }

  List<StreamCandidate> _buildCandidates(
    Iterable<String> values, {
    required Uri baseUri,
  }) {
    final result = <StreamCandidate>[];
    final seen = <String>{};
    var index = 0;

    for (final raw in values) {
      final uri = _resolveUri(raw, baseUri);
      if (uri == null || !seen.add(uri.toString())) continue;

      result.add(
        StreamCandidate(
          id: 'generic:${_configId()}:${index++}',
          label: config.name,
          uri: uri,
          quality: _qualityHint(uri),
          backend: PlaybackBackend.native,
          headers: Map<String, String>.unmodifiable(
            config.headers ?? const <String, String>{},
          ),
        ),
      );
    }

    return result;
  }

  Uri? _resolveUri(String raw, Uri baseUri) {
    var value = _cleanValue(raw);
    if (value.isEmpty) return null;

    if (value.startsWith('//')) {
      value = '${baseUri.scheme}:$value';
    }

    final parsed = Uri.tryParse(value);
    if (parsed == null) return null;

    final resolved = parsed.isAbsolute ? parsed : baseUri.resolveUri(parsed);
    if (resolved.scheme != 'http' && resolved.scheme != 'https') return null;
    return resolved;
  }

  Uri? _httpUri(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return null;
    }
    return uri;
  }

  String _cleanValue(String raw) {
    var value = raw.trim();
    if (value.length >= 2) {
      final first = value.codeUnitAt(0);
      final last = value.codeUnitAt(value.length - 1);
      if ((first == 34 && last == 34) || (first == 39 && last == 39)) {
        value = value.substring(1, value.length - 1);
      }
    }

    value = value
        .replaceAll(r'\/', '/')
        .replaceAll(r'\u0026', '&')
        .replaceAll(r'\u003d', '=')
        .replaceAll(r'\u003f', '?');

    return html_parser.parseFragment(value).text ?? value;
  }

  List<String> _genericUrls(String input) {
    final expression = RegExp(
      r'''https?://[^\s"'<>]+''',
      caseSensitive: false,
    );
    return [
      for (final match in expression.allMatches(input))
        if (match.group(0) != null) match.group(0)!,
    ];
  }

  String _stripDataUri(String value) {
    final trimmed = value.trim();
    final comma = trimmed.indexOf(',');
    if (trimmed.startsWith('data:') && comma >= 0) {
      return trimmed.substring(comma + 1).replaceAll(RegExp(r'\s+'), '');
    }
    return trimmed.replaceAll(RegExp(r'\s+'), '');
  }

  bool _containsHeader(Map<String, String> headers, String name) {
    final needle = name.toLowerCase();
    return headers.keys.any((key) => key.toLowerCase() == needle);
  }

  String _configId() {
    final value = config.name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return value.isEmpty ? 'extractor' : value;
  }

  String? _qualityHint(Uri uri) {
    final value = uri.toString().toLowerCase();
    if (value.contains('2160') || value.contains('4k')) return '2160p';
    if (value.contains('1080')) return '1080p';
    if (value.contains('720')) return '720p';
    if (value.contains('480')) return '480p';
    if (value.contains('360')) return '360p';
    return null;
  }
}
