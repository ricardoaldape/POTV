import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:potv/data/live_tv/live_tv_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late Dio dio;
  var serviceAvailable = true;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('potv-tv-test-');
    serviceAvailable = true;
    dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (!serviceAvailable) {
            return handler.reject(DioException(
              requestOptions: options,
              response: Response(
                requestOptions: options,
                statusCode: 503,
                statusMessage: 'Provider offline',
              ),
              type: DioExceptionType.badResponse,
            ));
          }
          return handler.resolve(Response<String>(
            requestOptions: options,
            statusCode: 200,
            data: '#EXTM3U\n'
                '#EXTINF:-1 tvg-id="demo" group-title="Testing",Demo TV\n'
                'https://example.org/channel.m3u8\n',
          ));
        },
      ),
    );
  });

  tearDown(() async {
    dio.close(force: true);
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  test('keeps last valid private playlist after provider outage', () async {
    final repository = LiveTvRepository(dio, supportDirectory: directory);
    await repository.saveSource('https://provider.example/tv');
    final first = await repository.loadChannels();
    expect(first, hasLength(1));
    expect(first.single.name, 'Demo TV');

    serviceAvailable = false;
    final second = await repository.loadChannels();
    expect(second, hasLength(1));
    expect(second.single.name, 'Demo TV');
  });

  test('does not reuse previous cache when provider changes', () async {
    final repository = LiveTvRepository(dio, supportDirectory: directory);
    await repository.saveSource('https://provider.example/first');
    expect(await repository.loadChannels(), hasLength(1));

    serviceAvailable = false;
    await repository.saveSource('https://different.example/tv');
    await expectLater(repository.loadChannels(), throwsA(isA<DioException>()));
  });
}
