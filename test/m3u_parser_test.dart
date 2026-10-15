import 'package:flutter_test/flutter_test.dart';
import 'package:potv/data/live_tv/m3u_parser.dart';

void main() {
  test('EXTINF quoted browser User-Agent comma never becomes channel title', () {
    const raw = '#EXTM3U\n'
        '#EXTINF:-1 http-user-agent="Mozilla/5.0 (KHTML, like Gecko) Chrome/154.0" group-title="Sports",ESPN 2 Latin America\n'
        'https://example.com/espn2.m3u8\n';

    final channels = M3uParser.parse(raw);
    expect(channels, hasLength(1));
    expect(channels.single.name, 'ESPN 2 Latin America');
    expect(channels.single.group, 'Sports');
    expect(channels.single.name.toLowerCase(), isNot(contains('gecko')));
  });

  test('broken quoted metadata cannot leak browser text into name', () {
    const raw = '#EXTM3U\n'
        '#EXTINF:-1 http-user-agent="Mozilla/5.0 (KHTML, like Gecko),Unreliable\n'
        'https://example.com/unreliable.m3u8\n';

    final channels = M3uParser.parse(raw);
    expect(channels, hasLength(1));
    expect(channels.single.name, 'Canal 1');
  });

  test('parses M3U channel metadata and stream URL', () {
    const raw = '#EXTM3U\n'
        '#EXTINF:-1 tvg-id="demo" tvg-name="Canal Demo" group-title="Noticias",Canal Demo\n'
        'https://example.com/live.m3u8\n';

    final channels = M3uParser.parse(raw);

    expect(channels, hasLength(1));
    expect(channels.first.name, 'Canal Demo');
    expect(channels.first.epgId, 'demo');
    expect(channels.first.group, 'Noticias');
    expect(
      channels.first.stream.uri.toString(),
      'https://example.com/live.m3u8',
    );
  });

  test('parses playback headers and embedded EPG URL', () {
    const raw = '#EXTM3U url-tvg="https://example.com/guide.xml"\n'
        '#EXTINF:-1 tvg-name="Canal Seguro",Canal Seguro\n'
        '#EXTVLCOPT:http-user-agent=POTV-Test\n'
        'https://example.com/live.m3u8|Referer=https%3A%2F%2Forigin.example%2F\n';

    final channels = M3uParser.parse(raw);
    final epg = M3uParser.epgUri(raw);

    expect(channels, hasLength(1));
    expect(channels.first.stream.headers['User-Agent'], 'POTV-Test');
    expect(
      channels.first.stream.headers['Referer'],
      'https://origin.example/',
    );
    expect(epg.toString(), 'https://example.com/guide.xml');
  });
}
