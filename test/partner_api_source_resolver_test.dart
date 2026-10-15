import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:potv/data/resolution/partner_api_source_resolver.dart';
import 'package:potv/domain/resolution/provider_resolver.dart';
import 'package:potv/domain/models/stream_candidate.dart';

void main() {
  test('VOD route resolves playable server data and passes session headers',
      () async {
    final requested = <Uri>[];
    final dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      requested.add(options.uri);
      expect(options.followRedirects, isFalse);
      expect(options.maxRedirects, 0);
      expect(options.headers['Authorization'], 'Bearer authorized-test-only');
      handler.resolve(Response<Object?>(
        requestOptions: options,
        statusCode: 200,
        data: {
          'count': 2,
          'sources': [
            {
              'provider': 'Latino',
              'real_url': 'https://cdn.example/movie/101.m3u8',
              'url': 'https://landing.example/',
              'language': 'es-MX',
              'quality': '1080p',
            },
            {
              'provider': 'Web fallback',
              'embed_url': 'https://embed.example/player',
              'requires_extraction': true,
              'language': 'en',
            },
          ],
        },
      ));
    }));
    final resolver = PartnerApiSourceResolver(
      baseUrl: Uri.parse('https://authorized.example/api/v1'),
      dio: dio,
      sessionHeaders: () async => {
        'Authorization': 'Bearer authorized-test-only',
      },
    );
    final results = await resolver.resolve(const ProviderResolveRequest(
      mediaType: 'movie',
      mediaId: '101',
      title: 'Sample Movie',
      externalId: 'tt1234567',
    ));
    expect(results, hasLength(2));
    expect(requested.single.path, '/api/v1/vod/sources/movie/101');
    expect(requested.single.queryParameters['language'], 'es-MX');
    expect(results.first.uri.host, 'cdn.example');
    expect(results.first.backend, PlaybackBackend.native);
    expect(results.last.backend, PlaybackBackend.webView);
  });

  test('legacy source route runs when VOD endpoint is unavailable', () async {
    final requests = <String>[];
    final dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      requests.add(options.uri.path);
      if (requests.length == 1) {
        handler.reject(DioException(
          requestOptions: options,
          response: Response<Object?>(
            requestOptions: options,
            statusCode: 404,
          ),
          type: DioExceptionType.badResponse,
        ));
      } else {
        handler.resolve(Response<Object?>(
          requestOptions: options,
          statusCode: 200,
          data: {
            'sources': [
              {
                'embed_url': 'https://embed.example/tv',
                'requires_extraction': true,
              }
            ]
          },
        ));
      }
    }));
    final resolver = PartnerApiSourceResolver(
      baseUrl: Uri.parse('https://authorized.example/api/'),
      dio: dio,
    );
    final result = await resolver.resolve(const ProviderResolveRequest(
      mediaType: 'tv',
      mediaId: '202',
      season: 1,
      episode: 2,
    ));
    expect(requests, [
      '/api/vod/sources/tv/202/1/2',
      '/api/sources/tv/202/1/2',
    ]);
    expect(result.single.backend, PlaybackBackend.webView);
  });

  test('unauthorized session never falls back to private source routes',
      () async {
    var count = 0;
    final dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      count++;
      handler.reject(DioException(
        requestOptions: options,
        response: Response<Object?>(
          requestOptions: options,
          statusCode: 403,
        ),
        type: DioExceptionType.badResponse,
      ));
    }));
    final resolver = PartnerApiSourceResolver(
      baseUrl: Uri.parse('https://authorized.example/api/'),
      dio: dio,
    );
    final result = await resolver.resolve(const ProviderResolveRequest(
      mediaType: 'movie',
      mediaId: '400',
    ));
    expect(result, isEmpty);
    expect(count, 1);
  });
}
