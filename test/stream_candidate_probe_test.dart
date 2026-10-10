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
      InterceptorsWrapper(onRequest: (options, handler) {
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
      }),
    );

    final candidates = await StreamCandidateProbe(dio)
        .preferReachable([_signedEmbed('video')]);
    expect(candidates, hasLength(1));
    expect(candidates.single.backend, PlaybackBackend.native);
    expect(candidates.single.id, 'video');
    expect(candidates.single.uri.queryParameters['signature'], 'test');
  });

  test('HTML page remains WebView after HEAD probe', () async {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(onRequest: (options, handler) {
        handler.resolve(
          Response<Object?>(
            requestOptions: options,
            statusCode: 200,
            headers: Headers.fromMap({
              'content-type': ['text/html; charset=utf-8'],
            }),
          ),
        );
      }),
    );

    final candidates = await StreamCandidateProbe(dio)
        .preferReachable([_signedEmbed('embed')]);
    expect(candidates.single.backend, PlaybackBackend.webView);
  });

  test('HEAD failure never discards the only candidate', () async {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(onRequest: (options, handler) {
        handler.reject(DioException(
          requestOptions: options,
          type: DioExceptionType.connectionTimeout,
        ));
      }),
    );

    final candidates = await StreamCandidateProbe(dio)
        .preferReachable([_signedEmbed('head-not-allowed')]);
    expect(candidates.single.backend, PlaybackBackend.webView);
  });
}
