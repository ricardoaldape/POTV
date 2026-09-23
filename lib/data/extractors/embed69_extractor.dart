import 'package:dio/dio.dart';

import '../../domain/models/stream_candidate.dart';
import '../../domain/resolution/provider_resolver.dart';

class Embed69Extractor {
  final Dio _dio;

  const Embed69Extractor({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 12),
                receiveTimeout: const Duration(seconds: 20),
                headers: {
                  'User-Agent':
                      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
                  'Accept': 'text/html,application/xhtml+xml,application/xml,*/*',
                },
              ),
            );

  Future<String?> extractDirectUrl(String embedUrl) async {
    final source = embedUrl.trim();
    if (source.isEmpty) return null;

    final normalized = _normalizeUrl(source);
    if (normalized == null) return null;

    final uri = Uri.tryParse(normalized);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return null;
    }

    if (_looksLikeDirectMedia(normalized)) {
      return normalized;
    }

    try {
      final response = await _dio.getUri(
        uri,
        options: Options(
          responseType: ResponseType.plain,
          followRedirects: true,
        ),
      );

      final html = response.data?.toString() ?? '';
      final candidates = _collectMediaUrls(html, normalized);
      if (candidates.isEmpty) {
        return null;
      }
      return candidates.first;
    } on DioException {
      return null;
    }
  }

  String? _normalizeUrl(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;

    final url = Uri.tryParse(trimmed);
    if (url != null && url.isAbsolute) return url.toString();
    return null;
  }

  List<String> _collectMediaUrls(String html, String baseUrl) {
    final matches = <String>{};

    final direct = RegExp(
      r'https?:\/\/[^\s"\'<>]+\.(?:m3u8|mp4|m4v|webm)(?:\?[^\s"\'<>]*)?',
      caseSensitive: false,
    );
    for (final match in direct.allMatches(html)) {
      final value = match.group(0);
      if (value != null && value.isNotEmpty) {
        matches.add(value);
      }
    }

    final keyValue = RegExp(
      r'''(?i)(?:file|src|source|url|manifest|playlist|video)\s*[:=]\s*["']?(https?:\/\/[^"'\s>]+)''',
    );
    for (final match in keyValue.allMatches(html)) {
      final value = match.group(1);
      if (value != null) {
        matches.add(value);
      }
    }

    final jsonLike = RegExp(
      r'''(?i)(?:"|')?(?:file|src|source|url|manifest|playlist|video)(?:"|')?\s*:\s*(?:"|')?(https?:\/\/[^"'\s]+)''',
    );
    for (final match in jsonLike.allMatches(html)) {
      final value = match.group(1);
      if (value != null) {
        matches.add(value);
      }
    }

    final resolved = <String>[];
    for (final value in matches) {
      final normalized = _resolveAbsoluteUrl(value, baseUrl);
      if (_looksLikeDirectMedia(normalized)) {
        resolved.add(normalized);
      }
    }

    return resolved;
  }

  String _resolveAbsoluteUrl(String raw, String baseUrl) {
    try {
      final uri = Uri.tryParse(raw);
      if (uri != null && uri.isAbsolute) return uri.toString();
      return Uri.parse(baseUrl).resolve(raw).toString();
    } catch (_) {
      return raw;
    }
  }

  bool _looksLikeDirectMedia(String value) {
    final lower = value.toLowerCase();
    return lower.contains('.m3u8') ||
        lower.contains('.mp4') ||
        lower.contains('.m4v') ||
        lower.contains('.webm');
  }
}

class Embed69ProviderResolver extends ProviderResolver {
  final Embed69Extractor extractor;
  final bool enabled;

  const Embed69ProviderResolver({
    required this.extractor,
    this.enabled = true,
  });

  @override
  String get id => 'embed69';

  @override
  String get displayName => 'Embed69';

  @override
  int get priority => 55;

  @override
  Set<String> get supportedMediaTypes => const {'movie', 'tv', 'anime'};

  @override
  Future<List<StreamCandidate>> resolve(ProviderResolveRequest request) async {
    if (!enabled || request.embedUrl == null || request.embedUrl!.trim().isEmpty) {
      return const [];
    }

    final directUrl = await extractor.extractDirectUrl(request.embedUrl!);
    if (directUrl == null) {
      return const [];
    }

    final uri = Uri.tryParse(directUrl);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return const [];
    }

    return [
      StreamCandidate(
        id: 'embed69:${uri.host}:${uri.path}',
        label: 'Embed69',
        uri: uri,
        quality: _qualityHint(directUrl),
        backend: PlaybackBackend.native,
      ),
    ];
  }

  String? _qualityHint(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('720')) return '720p';
    if (lower.contains('1080')) return '1080p';
    if (lower.contains('480')) return '480p';
    return 'Direct';
  }
}
