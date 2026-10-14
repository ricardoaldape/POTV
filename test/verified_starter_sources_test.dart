import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:potv/data/live_tv/built_in_live_sources.dart';

void main() {
  test('only decoder-tested built-in streams are returned offline', () async {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          fail('built-in fallback should never request remote playlists');
        },
      ),
    );
    final registry = BuiltInLiveSourceRegistry(dio);
    expect((await registry.mexico()).map((e) => e.name), ['ADN 40']);
    expect((await registry.sports()).map((e) => e.name), [
      'FIFA+ Hispanic America',
      'Red Bull TV ES',
    ]);
  });
}
