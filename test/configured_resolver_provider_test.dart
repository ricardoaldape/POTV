import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:potv/data/resolution/configured_resolver_provider.dart';
import 'package:potv/domain/resolution/provider_resolver.dart';
import 'package:potv/domain/models/stream_candidate.dart';
import 'package:potv/domain/resolution/resolver_endpoint_config.dart';

void main() {
  test('resolver endpoint config validates media types', () {
    final config = ResolverEndpointConfig.fromJson({
      'id': 'demo',
      'name': 'Demo Resolver',
      'endpoint': 'https://resolver.example/resolve',
      'media_types': ['movie', 'tv', 'anime'],
      'priority': 12,
    });

    expect(config.id, 'demo');
    expect(config.priority, 12);
    expect(config.mediaTypes, {'movie', 'tv', 'anime'});
  });

  test('configured resolver sends normalized identity and parses streams',
      () async {
    final dio = Dio();
    Uri? requested;

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requested = options.uri;
          handler.resolve(
            Response<Object?>(
              requestOptions: options,
              statusCode: 200,
              data: {
                'streams': [
                  {
                    'server': 'Servidor Uno',
                    'url': 'https://cdn.example/video.m3u8',
                    'idioma': 'es-MX',
                    'calidad': '1080p',
                    'headers': {'Referer': 'https://resolver.example/'},
                  },
                ],
              },
            ),
          );
        },
      ),
    );

    final provider = ConfiguredResolverProvider(
      ResolverEndpointConfig.fromJson({
        'id': 'demo',
        'name': 'Demo Resolver',
        'endpoint': 'https://resolver.example/resolve',
        'media_types': ['tv'],
      }),
      dio: dio,
    );

    final streams = await provider.resolve(
      const ProviderResolveRequest(
        mediaType: 'tv',
        mediaId: '1399',
        externalId: 'tt0944947',
        title: 'Game of Thrones',
        year: '2011',
        season: 2,
        episode: 4,
      ),
    );

    expect(requested, isNotNull);
    expect(requested!.queryParameters['type'], 'tv');
    expect(requested!.queryParameters['tmdb_id'], '1399');
    expect(requested!.queryParameters['external_id'], 'tt0944947');
    expect(requested!.queryParameters['season'], '2');
    expect(requested!.queryParameters['episode'], '4');

    expect(streams, hasLength(1));
    expect(streams.first.language, 'es-MX');
    expect(streams.first.quality, '1080p');
    expect(streams.first.headers['Referer'], 'https://resolver.example/');
  });

  test('configured anime resolver uses AniList id', () async {
    final dio = Dio();
    Uri? requested;

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requested = options.uri;
          handler.resolve(
            Response<Object?>(
              requestOptions: options,
              statusCode: 200,
              data: const {'streams': []},
            ),
          );
        },
      ),
    );

    final provider = ConfiguredResolverProvider(
      ResolverEndpointConfig.fromJson({
        'id': 'anime-demo',
        'name': 'Anime Demo',
        'endpoint': 'https://resolver.example/anime',
        'media_types': ['anime'],
      }),
      dio: dio,
    );

    await provider.resolve(
      const ProviderResolveRequest(
        mediaType: 'anime',
        mediaId: '20',
        title: 'Naruto',
        episode: 53,
      ),
    );

    expect(requested, isNotNull);
    expect(requested!.queryParameters['anilist_id'], '20');
    expect(requested!.queryParameters.containsKey('tmdb_id'), isFalse);
    expect(requested!.queryParameters['episode'], '53');
  });
  test('configured resolver accepts servidores response schema', () async {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(
            Response<Object?>(
              requestOptions: options,
              statusCode: 200,
              data: {
                'servidores': [
                  {
                    'servidor_nombre': 'Servidor Latino',
                    'servidor_url': 'https://cdn.example/latino.m3u8',
                    'idioma': 'es_MX',
                    'calidad': 'HD',
                  },
                ],
              },
            ),
          );
        },
      ),
    );

    final provider = ConfiguredResolverProvider(
      ResolverEndpointConfig.fromJson({
        'id': 'legacy-schema',
        'name': 'Legacy',
        'endpoint': 'https://resolver.example/resolve',
        'media_types': ['movie'],
      }),
      dio: dio,
    );

    final streams = await provider.resolve(
      const ProviderResolveRequest(
        mediaType: 'movie',
        mediaId: '1',
      ),
    );

    expect(streams, hasLength(1));
    expect(streams.first.uri.toString(), 'https://cdn.example/latino.m3u8');
    expect(streams.first.language, 'es_MX');
  });


  test('non media resolver URL defaults to in-app webView', () async {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(
            Response<Object?>(
              requestOptions: options,
              statusCode: 200,
              data: {
                'streams': [
                  {
                    'name': 'Embed',
                    'url': 'https://embed.example/player/123',
                  },
                ],
              },
            ),
          );
        },
      ),
    );

    final provider = ConfiguredResolverProvider(
      ResolverEndpointConfig.fromJson({
        'id': 'embed-demo',
        'name': 'Embed Demo',
        'endpoint': 'https://resolver.example/resolve',
        'media_types': ['movie'],
      }),
      dio: dio,
    );

    final streams = await provider.resolve(
      const ProviderResolveRequest(
        mediaType: 'movie',
        mediaId: '1',
      ),
    );

    expect(streams.single.backend.name, 'webView');
  });

  test('partner gateway envelope and MIME classify signed media', () async {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(onRequest: (options, handler) {
        handler.resolve(
          Response<Object?>(
            requestOptions: options,
            statusCode: 200,
            data: {
              'data': {
                'sources': [
                  {
                    'name': 'Partner CDN',
                    'streamUrl': 'https://media.example/play?id=123',
                    'content_type': 'video/mp4',
                    'language': 'es-MX',
                    'headers': {'X-Media-Token': 'opaque'},
                  },
                ],
              },
            },
          ),
        );
      }),
    );
    final provider = ConfiguredResolverProvider(
      ResolverEndpointConfig.fromJson({
        'id': 'partner',
        'name': 'Partner gateway',
        'endpoint': 'https://partner-gateway.example/resolve',
        'media_types': ['movie'],
      }),
      dio: dio,
    );
    final streams = await provider.resolve(
      const ProviderResolveRequest(mediaType: 'movie', mediaId: '101'),
    );
    expect(streams, hasLength(1));
    expect(streams.single.backend.name, 'native');
    expect(streams.single.language, 'es-MX');
    expect(streams.single.headers['X-Media-Token'], 'opaque');
  });
  test('server list updates, backups, and disabled sources require no APK update',
      () async {
    var revision = 1;
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(onRequest: (options, handler) {
        handler.resolve(Response<Object?>(
          requestOptions: options,
          statusCode: 200,
          data: {
            'data': {
              'revision': revision.toString(),
              'servers': [
                {
                  'name': 'Latino',
                  'language': 'es-MX',
                  'content_type': 'application/vnd.apple.mpegurl',
                  'stream_url': 'https://cdn.example/hls/live',
                  'backup_urls': [
                    'https://backup.example/hls/live'
                  ],
                },
                if (revision >= 2)
                  {
                    'name': 'New provider',
                    'streamUrl': 'https://new.example/play?id=1',
                    'content_type': 'video/mp4',
                  },
                {
                  'name': 'Blocked',
                  'enabled': false,
                  'url': 'https://disabled.example/test.mp4',
                },
              ],
            }
          },
        ));
      }),
    );
    final provider = ConfiguredResolverProvider(
      ResolverEndpointConfig.fromJson({
        'id': 'partner',
        'name': 'POTV',
        'endpoint': 'https://gateway.example/sources',
        'media_types': ['movie'],
      }),
      dio: dio,
    );
    final request = ProviderResolveRequest(mediaType: 'movie', mediaId: '123');
    final first = await provider.resolve(request);
    expect(first, hasLength(2));
    expect(first.first.label, contains('Servidor 1'));
    expect(first.last.label, contains('respaldo 1'));
    expect(first.first.language, 'es-MX');
    expect(first.last.uri.host, 'backup.example');

    revision = 2;
    final updated = await provider.resolve(request);
    expect(updated, hasLength(3));
    expect(updated.last.label, contains('Servidor 2'));
    expect(updated.last.uri.host, 'new.example');
    expect(updated.last.backend.name, 'native');
    expect(updated.any((s) => s.uri.host == 'disabled.example'), isFalse);
  });

  test('native partner URL wins over HTML embed in one source response', () {
    final provider = ConfiguredResolverProvider(
      ResolverEndpointConfig.fromJson({
        'id': 'dual',
        'name': 'Partner',
        'endpoint': 'https://api.example.test/resolve',
        'media_types': ['movie'],
      }),
    );
    final streams = provider.parseResponse({
      'streams': [
        {
          'name': 'Video de prueba',
          'backend': 'webview',
          'is_iframe': true,
          'requires_extraction': true,
          'stream_url': 'https://cdn.example.test/video/master.m3u8',
          'embed_url': 'https://player.example.test/embed/demo',
          'language': 'es-419',
          'headers': {'Authorization': 'Bearer demo-private-value'},
        },
      ],
    });
    expect(streams, hasLength(2));
    expect(streams.first.backend, PlaybackBackend.native);
    expect(streams.first.uri.host, 'cdn.example.test');
    expect(streams.first.language, 'es-419');
    expect(streams.last.backend, PlaybackBackend.webView);
    expect(streams.last.uri.host, 'player.example.test');
    expect(streams.last.headers, isEmpty,
        reason: 'CDN credentials must never reach an HTML embed.');
  });

  test('extensionless authorized video remains native with MIME evidence', () {
    final provider = ConfiguredResolverProvider(
      ResolverEndpointConfig.fromJson({
        'id': 'signed',
        'name': 'Signed partner',
        'endpoint': 'https://api.example.test/resolve',
        'media_types': ['tv'],
      }),
    );
    final streams = provider.parseResponse({
      'streams': [
        {
          'streamUrl': 'https://cdn.example.test/play?session=demo',
          'embedUrl': 'https://player.example.test/view/demo',
          'content_type': 'application/vnd.apple.mpegurl',
          'is_iframe': true,
        },
      ],
    });
    expect(streams, hasLength(2));
    expect(streams.first.backend, PlaybackBackend.native);
    expect(streams.last.backend, PlaybackBackend.webView);
  });

  test('HTML-only source is never incorrectly labelled native', () {
    final provider = ConfiguredResolverProvider(
      ResolverEndpointConfig.fromJson({
        'id': 'html',
        'name': 'HTML partner',
        'endpoint': 'https://api.example.test/resolve',
        'media_types': ['movie'],
      }),
    );
    final streams = provider.parseResponse({
      'streams': [
        {'embed_url': 'https://player.example.test/embed/demo', 'is_iframe': true},
      ],
    });
    expect(streams, hasLength(1));
    expect(streams.single.backend, PlaybackBackend.webView);
  });

}
