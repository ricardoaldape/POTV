import '../../domain/models/stremio_addon_config.dart';
import '../../domain/models/stream_candidate.dart';

class StremioProtocol {
  const StremioProtocol._();

  static String? streamId({
    required String mediaType,
    required String mediaId,
    String? externalId,
    int? season,
    int? episode,
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

  static Uri streamUri({
    required StremioAddonConfig addon,
    required String type,
    required String itemId,
  }) {
    final encodedId = Uri.encodeComponent(itemId);
    return addon.manifestUri.resolve(
      'stream/$type/$encodedId.json',
    );
  }

  static List<StreamCandidate> parseStreams({
    required StremioAddonConfig addon,
    required Object? raw,
  }) {
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
  }

  static Map<String, String> _requestHeaders(Object? behaviorHints) {
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

  static String? _language(Map<String, dynamic> value) {
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

  static String? _quality(Map<String, dynamic> value) {
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

  static String? _text(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
}
