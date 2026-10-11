import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:potv/data/live_tv/live_tv_repository.dart';

String playlist(String id, String name, String url, {String category = 'Noticias'}) =>
    '#EXTM3U\n'
    '#EXTINF:-1 tvg-id="$id" tvg-name="$name" group-title="$category",$name\n'
    '$url\n';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('adding a second M3U preserves the existing playlist and channel backups',
      () async {
    final dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        final first = options.uri.host == 'first.example';
        handler.resolve(Response<String>(
          requestOptions: options,
          statusCode: 200,
          data: first
              ? playlist('news-1', 'POTV Noticias', 'https://cdn1.example/hls')
              : playlist('news-1', 'POTV Noticias', 'https://cdn2.example/hls'),
        ));
      },
    ));
    final repo = LiveTvRepository(dio);
    await repo.saveSource('https://first.example/list.m3u');
    await repo.saveSource('https://second.example/list.m3u');
    expect(await repo.configuredSources(), hasLength(2));
    final channels = await repo.loadChannels();
    expect(channels, hasLength(1));
    expect(channels.single.playbackCandidates, hasLength(2));
    expect(channels.single.playbackCandidates.first.uri.host, 'cdn1.example');
    expect(channels.single.playbackCandidates.last.uri.host, 'cdn2.example');
  });

  test('unavailable M3U source cannot hide channels from healthy source',
      () async {
    final dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      if (options.uri.host == 'offline.example') {
        handler.reject(DioException(
          requestOptions: options,
          type: DioExceptionType.connectionTimeout,
        ));
      } else {
        handler.resolve(Response<String>(
          requestOptions: options,
          statusCode: 200,
          data: playlist('sport-1', 'FIFA+', 'https://video.example/live',
              category: 'Deportes'),
        ));
      }
    }));
    final repo = LiveTvRepository(dio);
    await repo.saveSource('https://offline.example/playlist.m3u');
    await repo.saveSource('https://ok.example/playlist.m3u');
    final channels = await repo.loadChannels();
    expect(channels, hasLength(1));
    expect(channels.single.name, 'FIFA+');
    final configured = await repo.configuredSources();
    expect(configured.map((s) => s.label), contains('offline.example'));
  });

  test('legacy playlist URL is migrated and existing favorites are unaffected',
      () async {
    SharedPreferences.setMockInitialValues({
      'live_tv_m3u_url': 'https://legacy.example/one.m3u',
      'live_tv_source_kind': 'url',
      'live_tv_favorite_channels': ['name:canal uno'],
    });
    final repo = LiveTvRepository(Dio());
    expect((await repo.configuredSources()).single.label, 'legacy.example');
    await repo.saveSource('https://new.example/two.m3u');
    expect((await repo.configuredSources()).map((s) => s.label),
        ['legacy.example', 'new.example']);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('live_tv_favorite_channels'),
        ['name:canal uno']);
  });

  test('source list labels do not display signed query credentials', () async {
    final repo = LiveTvRepository(Dio());
    await repo.saveSource('https://iptv.example/playlist?token=sensitive');
    expect((await repo.configuredSources()).single.label, 'iptv.example');
    await repo.removeSource(
        'url:https://iptv.example/playlist?token=sensitive');
    expect(await repo.configuredSources(), isEmpty);
  });

  test('rejects unsafe / malformed local source identifiers', () async {
    final repo = LiveTvRepository(Dio());
    await expectLater(
      repo.saveSource('file:///private/list.m3u'),
      throwsFormatException,
    );
    await expectLater(
      repo.saveSource('not a playlist'),
      throwsFormatException,
    );
  });
}
