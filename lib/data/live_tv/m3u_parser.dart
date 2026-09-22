import '../../domain/models/live_channel.dart';
import '../../domain/models/stream_candidate.dart';

class M3uParser {
  static List<LiveChannel> parse(String raw) {
    final lines = raw.split(RegExp(r'\r?\n'));
    final result = <LiveChannel>[];
    final pendingHeaders = <String, String>{};
    Map<String, String> attrs = const {};
    String? title;

    for (final original in lines) {
      final line = original.trim();
      if (line.isEmpty || line == '#EXTM3U') continue;

      if (line.startsWith('#EXTINF:')) {
        attrs = _attributes(line);
        final comma = line.indexOf(',');
        title = comma >= 0 ? line.substring(comma + 1).trim() : 'Canal';
        continue;
      }

      if (line.startsWith('#EXTVLCOPT:http-user-agent=')) {
        pendingHeaders['User-Agent'] =
            line.substring('#EXTVLCOPT:http-user-agent='.length).trim();
        continue;
      }

      if (line.startsWith('#EXTVLCOPT:http-referrer=') ||
          line.startsWith('#EXTVLCOPT:http-referer=')) {
        final equals = line.indexOf('=');
        pendingHeaders['Referer'] = line.substring(equals + 1).trim();
        continue;
      }

      if (line.startsWith('#')) continue;

      final parsed = _parseStream(line);
      if (parsed == null) continue;

      final index = result.length;
      final nextIndex = index + 1;
      final fallbackName = 'Canal $nextIndex';
      final name = (attrs['tvg-name']?.trim().isNotEmpty ?? false)
          ? attrs['tvg-name']!.trim()
          : (title?.isNotEmpty ?? false)
              ? title!
              : fallbackName;

      final headers = <String, String>{
        ...pendingHeaders,
        ...parsed.headers,
      };
      final logoText = attrs['tvg-logo'];

      result.add(
        LiveChannel(
          id: index.toString() + '-' + parsed.uri.toString(),
          name: name,
          group: attrs['group-title'],
          epgId: attrs['tvg-id'],
          logo: logoText == null ? null : Uri.tryParse(logoText),
          stream: StreamCandidate(
            id: 'm3u-$index',
            label: name,
            uri: parsed.uri,
            headers: headers,
            backend: PlaybackBackend.native,
          ),
        ),
      );

      attrs = const {};
      title = null;
      pendingHeaders.clear();
    }

    return result;
  }

  static Uri? epgUri(String raw) {
    for (final original in raw.split(RegExp(r'\r?\n'))) {
      final line = original.trim();
      if (line.isEmpty) continue;
      if (!line.startsWith('#EXTM3U')) return null;

      final attrs = _attributes(line);
      final value =
          attrs['url-tvg'] ?? attrs['x-tvg-url'] ?? attrs['tvg-url'];
      if (value == null || value.trim().isEmpty) return null;

      final first = value.split(',').first.trim();
      final uri = Uri.tryParse(first);
      return uri != null && uri.hasScheme ? uri : null;
    }
    return null;
  }

  static ({Uri uri, Map<String, String> headers})? _parseStream(
    String line,
  ) {
    final pipe = line.indexOf('|');
    final urlText = pipe < 0 ? line : line.substring(0, pipe).trim();
    final uri = Uri.tryParse(urlText);
    if (uri == null || !uri.hasScheme) return null;

    final headers = <String, String>{};
    if (pipe >= 0 && pipe + 1 < line.length) {
      final rawOptions = line.substring(pipe + 1);
      for (final option in rawOptions.split('&')) {
        final equals = option.indexOf('=');
        if (equals <= 0) continue;

        final rawKey = option.substring(0, equals);
        final rawValue = option.substring(equals + 1);
        final key = Uri.decodeQueryComponent(rawKey);
        final value = Uri.decodeQueryComponent(rawValue);
        headers[_canonicalHeader(key)] = value;
      }
    }

    return (uri: uri, headers: headers);
  }

  static String _canonicalHeader(String key) {
    switch (key.toLowerCase()) {
      case 'user-agent':
      case 'useragent':
        return 'User-Agent';
      case 'referer':
      case 'referrer':
        return 'Referer';
      case 'origin':
        return 'Origin';
      default:
        return key;
    }
  }

  static Map<String, String> _attributes(String line) {
    final out = <String, String>{};
    final matches = RegExp(r'([\w-]+)="([^"]*)"').allMatches(line);
    for (final m in matches) {
      out[m.group(1)!] = m.group(2)!;
    }
    return out;
  }
}
