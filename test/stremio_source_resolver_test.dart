import 'package:flutter_test/flutter_test.dart';
import 'package:potv/data/addons/stremio_protocol.dart';
import 'package:potv/domain/models/stremio_addon_config.dart';

void main() {
  const addon = StremioAddonConfig(
    id: 'demo-addon',
    name: 'Addon Demo',
    manifestUri: Uri(
      scheme: 'https',
      host: 'addon.example',
      path: '/manifest.json',
    ),
  );

  test('parses direct streams without requiring network access', () {
    final streams = StremioProtocol.parseStreams(
      addon: addon,
      raw: {
        'streams': [
          {
            'name': 'Latino 1080p',
            'url': 'https://cdn.example/movie.m3u8',
          },
          {
            'name': 'Torrent',
            'infoHash': 'deadbeef',
          },
        ],
      },
    );

    expect(streams, hasLength(1));
    expect(streams.first.uri.toString(), 'https://cdn.example/movie.m3u8');
    expect(streams.first.language, 'es-MX');
    expect(streams.first.quality, '1080p');
  });

  test('builds conventional Stremio movie and series ids', () {
    expect(
      StremioProtocol.streamId(
        mediaType: 'movie',
        mediaId: '123',
        externalId: 'tt1254207',
      ),
      'tt1254207',
    );

    expect(
      StremioProtocol.streamId(
        mediaType: 'tv',
        mediaId: '890',
        externalId: 'tt0279600',
        season: 1,
        episode: 3,
      ),
      'tt0279600:1:3',
    );
  });

  test('builds stream resource URL from manifest location', () {
    final uri = StremioProtocol.streamUri(
      addon: addon,
      type: 'series',
      itemId: 'tt0279600:1:3',
    );

    expect(
      uri.toString(),
      'https://addon.example/stream/series/tt0279600%3A1%3A3.json',
    );
  });
}
