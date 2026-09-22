import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:potv/data/resolution/configured_resolver_provider.dart';
import 'package:potv/domain/resolution/provider_resolver.dart';
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
}
