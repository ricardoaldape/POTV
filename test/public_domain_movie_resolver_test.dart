import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:potv/data/sources/public_domain_movie_resolver.dart';

void main() {
  test('resolves explicitly public-domain Archive movie to direct video', () async {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.path.contains('advancedsearch.php')) {
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'response': {
                    'docs': [
                      {
                        'identifier': 'night-of-the-living-dead_1968',
                        'title': 'Night of the Living Dead',
                        'year': 1968,
                        'licenseurl':
                            'https://creativecommons.org/publicdomain/mark/1.0/',
                      },
                    ],
                  },
                },
              ),
            );
            return;
          }

          if (options.path.contains('/metadata/')) {
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'metadata': {
                    'licenseurl':
                        'https://creativecommons.org/publicdomain/mark/1.0/',
                  },
                  'files': [
                    {
                      'name': 'Night of the Living Dead 720p.mp4',
                      'format': 'MPEG4',
                      'height': '720',
                      'size': '734003200',
                    },
                  ],
                },
              ),
            );
            return;
          }

          handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.badResponse,
            ),
          );
        },
      ),
    );

    final resolver = PublicDomainMovieResolver(dio);
    final streams = await resolver.resolve(
      mediaType: 'movie',
      title: 'Night of the Living Dead',
      year: '1968',
    );

    expect(streams, hasLength(1));
    expect(streams.first.label, contains('Dominio público'));
    expect(streams.first.quality, '720p');
    expect(
      streams.first.uri.toString(),
      contains('archive.org/download/night-of-the-living-dead_1968/'),
    );
    expect(streams.first.uri.toString(), endsWith('.mp4'));
  });

  test('does not expose Archive item without explicit public-domain license',
      () async {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(
            Response<Map<String, dynamic>>(
              requestOptions: options,
              statusCode: 200,
              data: {
                'response': {
                  'docs': [
                    {
                      'identifier': 'unlicensed-copy',
                      'title': 'Example Movie',
                      'year': 2025,
                      'licenseurl': 'https://example.com/unknown-license',
                    },
                  ],
                },
              },
            ),
          );
        },
      ),
    );

    final resolver = PublicDomainMovieResolver(dio);
    final streams = await resolver.resolve(
      mediaType: 'movie',
      title: 'Example Movie',
      year: '2025',
    );

    expect(streams, isEmpty);
  });
}
