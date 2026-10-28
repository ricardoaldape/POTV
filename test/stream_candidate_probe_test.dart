import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:potv/data/sources/stream_candidate_probe.dart';
import 'package:potv/domain/models/stream_candidate.dart';

StreamCandidate _signedEmbed(String id) => StreamCandidate(
  id: id,
  label: 'Partner source',
  uri: Uri.parse('https://media.example/watch/123?signature=test'),
  backend: PlaybackBackend.webView,
);

void main() {
  test('extensionless video is promoted to native playback', () async {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          expect(options.method, 'HEAD');
          handler.resolve(
            Response<Object?>(
              requestOptions: options,
              statusCode: 200,
              headers: Headers.fromMap({
                'content-type': ['video/mp4'],
              }),
            ),
          );
        },
      ),
    );

    final candidates = await StreamCandidateProbe(
      dio,
    ).preferReachable([_signedEmbed('video')]);
    expect(candidates, hasLength(1));
    expect(candidates.single.backend, PlaybackBackend.native);
    expect(candidates.single.id, 'video');
    expect(candidates.single.uri.queryParameters['signature'], 'test');
  });

  test('HTML page remains WebView after HEAD probe', () async {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(
            Response<Object?>(
              requestOptions: options,
              statusCode: 200,
              headers: Headers.fromMap({
                'content-type': ['text/html; charset=utf-8'],
              }),
            ),
          );
        },
      ),
    );

    final candidates = await StreamCandidateProbe(
      dio,
    ).preferReachable([_signedEmbed('embed')]);
    expect(candidates.single.backend, PlaybackBackend.webView);
  });

  test('HEAD failure never discards the only candidate', () async {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.connectionTimeout,
            ),
          );
        },
      ),
    );

    final candidates = await StreamCandidateProbe(
      dio,
    ).preferReachable([_signedEmbed('head-not-allowed')]);
    expect(candidates.single.backend, PlaybackBackend.webView);
  });

  test('authorized VOD sources are never probed with HEAD or GET', () async {
    var requests = 0;
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests++;
            handler.reject(
              DioException(
                requestOptions: options,
                response: Response(requestOptions: options, statusCode: 403),
                type: DioExceptionType.badResponse,
              ),
            );
          },
        ),
      );
    final signed = [
      StreamCandidate(
        id: 'potv_partner_api:1:0',
        label: 'POTV native',
        uri: Uri.parse('https://cdn.example/movie.m3u8?signature=short-lived'),
      ),
      StreamCandidate(
        id: 'potv_partner_api:2:0',
        label: 'POTV embed',
        uri: Uri.parse('https://embed.example/watch?signature=short-lived'),
        backend: PlaybackBackend.webView,
      ),
    ];
    final result = await StreamCandidateProbe(dio).preferReachable(signed);
    expect(requests, 0);
    expect(result, orderedEquals(signed));
  });

  test(
    'HLS probe timeout is inconclusive when another stream is healthy',
    () async {
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              if (options.method == 'GET') {
                handler.reject(
                  DioException(
                    requestOptions: options,
                    type: DioExceptionType.receiveTimeout,
                  ),
                );
              } else {
                handler.resolve(
                  Response(
                    requestOptions: options,
                    statusCode: 200,
                    headers: Headers.fromMap({
                      'content-type': ['video/mp4'],
                    }),
                  ),
                );
              }
            },
          ),
        );
      final hls = StreamCandidate(
        id: 'hls',
        label: 'HLS',
        uri: Uri.parse('https://media.example/live.m3u8'),
      );
      final mp4 = StreamCandidate(
        id: 'mp4',
        label: 'MP4',
        uri: Uri.parse('https://media.example/video.mp4'),
      );
      final result = await StreamCandidateProbe(
        dio,
      ).preferReachable([hls, mp4]);
      expect(result, hasLength(2));
      expect(result.first.id, 'mp4');
      expect(result.last.id, 'hls');
    },
  );
}
