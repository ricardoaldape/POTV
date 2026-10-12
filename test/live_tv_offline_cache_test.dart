import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:potv/data/live_tv/live_tv_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late HttpServer server;
  late Dio dio;
  var serviceAvailable = true;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('potv-tv-test-');
    serviceAvailable = true;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      if (!serviceAvailable) {
        request.response.statusCode = HttpStatus.serviceUnavailable;
      } else {
        request.response.headers.contentType = ContentType.text;
        request.response.write(
          '#EXTM3U\n'
          '#EXTINF:-1 tvg-id="demo" group-title="Testing",Demo TV\n'
          'https://example.org/channel.m3u8\n',
        );
      }
      await request.response.close();
    });
    dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 2),
      receiveTimeout: const Duration(seconds: 2),
    ));
  });

  tearDown(() async {
    dio.close(force: true);
    await server.close(force: true);
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  test('keeps an independently verified local playlist after 503', () async {
    final repository = LiveTvRepository(dio, supportDirectory: directory);
    await repository.saveSource('http://127.0.0.1:${server.port}/tv');
    final first = await repository.loadChannels();
    expect(first, hasLength(1));
    expect(first.single.name, 'Demo TV');

    serviceAvailable = false;
    final second = await repository.loadChannels();
    expect(second, hasLength(1));
    expect(second.single.name, 'Demo TV');
  });

  test('does not serve previous provider cache when URL changes', () async {
    final repository = LiveTvRepository(dio, supportDirectory: directory);
    await repository.saveSource('http://127.0.0.1:${server.port}/first');
    expect(await repository.loadChannels(), hasLength(1));

    serviceAvailable = false;
    await repository.saveSource('http://127.0.0.1:${server.port}/different');
    await expectLater(repository.loadChannels(), throwsA(isA<DioException>()));
  });
}
