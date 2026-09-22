import '../../domain/models/live_channel.dart';
import '../../domain/models/stream_candidate.dart';

class M3uParser {
  static List<LiveChannel> parse(String raw) {
    final lines = raw.split(RegExp(r'\r?\n'));
    final result = <LiveChannel>[];
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
      if (line.startsWith('#')) continue;

      final uri = Uri.tryParse(line);
      if (uri == null || !uri.hasScheme) continue;

      final index = result.length;
      final nextIndex = index + 1;
      final fallbackName = 'Canal $nextIndex';
      final name = (attrs['tvg-name']?.trim().isNotEmpty ?? false)
          ? attrs['tvg-name']!.trim()
          : (title?.isNotEmpty ?? false)
              ? title!
              : fallbackName;

      final logoText = attrs['tvg-logo'];
      result.add(
        LiveChannel(
          id: '$index-$uri',
          name: name,
          group: attrs['group-title'],
          epgId: attrs['tvg-id'],
          logo: logoText == null ? null : Uri.tryParse(logoText),
          stream: StreamCandidate(
            id: 'm3u-$index',
            label: name,
            uri: uri,
            backend: PlaybackBackend.native,
          ),
        ),
      );
      attrs = const {};
      title = null;
    }
    return result;
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
