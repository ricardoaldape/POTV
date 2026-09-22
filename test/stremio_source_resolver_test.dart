import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:potv/data/addons/stremio_addon_repository.dart';
import 'package:potv/data/addons/stremio_source_resolver.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('resolves direct HTTP streams from a Stremio-compatible addon',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));

    server.listen((request) async {
      if (request.uri.path == '/stream/movie/tt1254207.json') {
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'streams': [
              {
                'name': 'Latino 1080p',
                'url': 'https://example.com/movie.m3u8',
              }
            ],
          }),
        );
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });

    final manifestUri = Uri.parse(
      'http://127.0.0.1:${server.port}/manifest.json',
    );

    SharedPreferences.setMockInitialValues({
      'potv_stremio_addons': jsonEncode([
        {
          'id': 'test-addon',
          'name': 'Addon Demo',
          'manifest_uri': manifestUri.toString(),
          'enabled': true,
        }
      ]),
    });

    final resolver = StremioSourceResolver(
      const StremioAddonRepository(),
      Dio(),
    );

    final streams = await resolver.resolve(
      mediaType: 'movie',
      mediaId: '123',
      externalId: 'tt1254207',
      title: 'Big Buck Bunny',
    );

    expect(streams, hasLength(1));
    expect(streams.first.uri.toString(), 'https://example.com/movie.m3u8');
    expect(streams.first.language, 'es-MX');
    expect(streams.first.quality, '1080p');
  });

  test('builds the conventional Stremio series episode id', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));

    String? requestedPath;
    server.listen((request) async {
      requestedPath = request.uri.path;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'streams': []}));
      await request.response.close();
    });

    final manifestUri = Uri.parse(
      'http://127.0.0.1:${server.port}/manifest.json',
    );

    SharedPreferences.setMockInitialValues({
      'potv_stremio_addons': jsonEncode([
        {
          'id': 'series-addon',
          'name': 'Series Demo',
          'manifest_uri': manifestUri.toString(),
          'enabled': true,
        }
      ]),
    });

    final resolver = StremioSourceResolver(
      const StremioAddonRepository(),
      Dio(),
    );

    await resolver.resolve(
      mediaType: 'tv',
      mediaId: '890',
      externalId: 'tt0279600',
      title: 'Neon Genesis Evangelion',
      season: 1,
      episode: 3,
    );

    expect(requestedPath, contains('/stream/series/tt0279600'));
    expect(requestedPath, contains('1'));
    expect(requestedPath, contains('3.json'));
  });
}
