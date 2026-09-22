import 'package:flutter_test/flutter_test.dart';
import 'package:potv/data/live_tv/m3u_parser.dart';

void main() {
  test('parses M3U channel metadata and stream URL', () {
    const raw = '#EXTM3U\n'
        '#EXTINF:-1 tvg-id="demo" tvg-name="Canal Demo" group-title="Noticias",Canal Demo\n'
        'https://example.com/live.m3u8\n';

    final channels = M3uParser.parse(raw);

    expect(channels, hasLength(1));
    expect(channels.first.name, 'Canal Demo');
    expect(channels.first.epgId, 'demo');
    expect(channels.first.group, 'Noticias');
    expect(channels.first.stream.uri.toString(), 'https://example.com/live.m3u8');
  });
}
