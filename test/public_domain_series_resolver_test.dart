import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:potv/data/sources/public_domain_series_resolver.dart';

void main() {
  test('resolves public-domain series episode by season/episode markers',
      () async {
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
                        'identifier':
                            'thebeverlyhillbilliesmeanwhilebackatthecabinhq',
                        'title':
                            'The Beverly Hillbillies - Meanwhile, Back At The Cabin S01 E03',
                        'licenseurl':
                            'http://creativecommons.org/publicdomain/mark/1.0/',
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
                        'http://creativecommons.org/publicdomain/mark/1.0/',
                  },
                  'files': [
                    {
                      'name':
                          'The Beverly Hillbillies - Meanwhile, Back at the Cabin HQ.mp4',
                      'format': 'h.264',
                      'height': '480',
                      'size': '161190634',
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

    final resolver = PublicDomainSeriesResolver(dio);
    final streams = await resolver.resolve(
      mediaType: 'tv',
      title: 'The Beverly Hillbillies',
      season: 1,
      episode: 3,
    );

    expect(streams, hasLength(1));
    expect(streams.first.label, contains('T1 E3'));
    expect(streams.first.quality, '480p');
    expect(streams.first.uri.toString(), endsWith('.mp4'));
  });

  test('does not return a different episode from same series', () async {
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
                      'identifier': 'show-s01e04',
                      'title': 'Example Show S01 E04',
                      'licenseurl':
                          'https://creativecommons.org/publicdomain/mark/1.0/',
                    },
                  ],
                },
              },
            ),
          );
        },
      ),
    );

    final resolver = PublicDomainSeriesResolver(dio);
    final streams = await resolver.resolve(
      mediaType: 'tv',
      title: 'Example Show',
      season: 1,
      episode: 3,
    );

    expect(streams, isEmpty);
  });
}
