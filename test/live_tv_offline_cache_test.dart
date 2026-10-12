import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:potv/data/live_tv/built_in_live_sources.dart';
import 'package:potv/core/config/potv_runtime_flags.dart';
import 'package:potv/domain/models/live_channel.dart';
import 'package:potv/domain/models/stream_candidate.dart';
import 'package:potv/data/live_tv/live_tv_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _BrokenBuiltInFixture extends BuiltInLiveSourceRegistry {
  _BrokenBuiltInFixture() : super(Dio());

  @override
  Future<List<LiveChannel>> mexico() async =>
      throw StateError('Built-in catalogue offline');
}

class _BuiltInFixture extends BuiltInLiveSourceRegistry {
  _BuiltInFixture() : super(Dio());

  @override
  Future<List<LiveChannel>> mexico() async => [
        LiveChannel(
          id: 'safe-public',
          name: 'Public TV',
          stream: StreamCandidate(
            id: 'public-stream',
            label: 'Public TV',
            uri: Uri.parse('https://example.org/public.m3u8'),
          ),
        ),
      ];
}

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
  test('provider outage still shows built-in channels', () async {
    final repository = LiveTvRepository(dio, supportDirectory: directory);
    await repository.saveSource('https://offline.example/list.m3u');
    serviceAvailable = false;

    final flags = PotvRuntimeFlagStore(await SharedPreferences.getInstance());
    final container = ProviderContainer(overrides: [
      potvRuntimeFlagStoreProvider.overrideWith((ref) => flags),
      liveTvRepositoryProvider.overrideWithValue(repository),
      builtInLiveSourceRegistryProvider.overrideWithValue(_BuiltInFixture()),
    ]);
    addTearDown(container.dispose);

    final channels = await container.read(liveChannelsProvider.future);
    expect(channels, hasLength(1));
    expect(channels.single.name, 'Public TV');
  });


  test('runtime kill switch disables only integrated channel catalogue', () async {
    final repository = LiveTvRepository(dio, supportDirectory: directory);
    await repository.saveSource('https://configured.example/custom.m3u');

    final flags = PotvRuntimeFlagStore(await SharedPreferences.getInstance());
    expect(await flags.applyVerifiedManifest(
      '{"version":1,"flags":{"live_tv_catalog":false}}',
    ), isTrue);

    final container = ProviderContainer(overrides: [
      potvRuntimeFlagStoreProvider.overrideWith((ref) => flags),
      liveTvRepositoryProvider.overrideWithValue(repository),
      builtInLiveSourceRegistryProvider.overrideWithValue(_BuiltInFixture()),
    ]);
    addTearDown(container.dispose);

    final channels = await container.read(liveChannelsProvider.future);
    expect(channels.map((item) => item.name), ['Demo TV']);
  });

  test('personal M3U survives a failed built-in TV catalogue', () async {
    final repository = LiveTvRepository(dio, supportDirectory: directory);
    await repository.saveSource('https://myprovider.example/tv');
    final flags = PotvRuntimeFlagStore(await SharedPreferences.getInstance());
    final container = ProviderContainer(overrides: [
      potvRuntimeFlagStoreProvider.overrideWith((ref) => flags),
      liveTvRepositoryProvider.overrideWithValue(repository),
      builtInLiveSourceRegistryProvider.overrideWithValue(
        _BrokenBuiltInFixture(),
      ),
    ]);
    addTearDown(container.dispose);

    final channels = await container.read(liveChannelsProvider.future);
    expect(channels, hasLength(1));
    expect(channels.single.name, 'Demo TV');
  });

}
