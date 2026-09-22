import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:potv/data/addons/stremio_addon_repository.dart';
import 'package:potv/data/sports/addon_sports_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads live sports catalog and resolves direct streams', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);

    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;

      switch (request.uri.path) {
        case '/manifest.json':
          request.response.write(jsonEncode({
            'id': 'sports.test',
            'name': 'Sports Test',
            'version': '1.0.0',
            'resources': ['catalog', 'stream'],
            'types': ['tv'],
            'catalogs': [
              {
                'type': 'tv',
                'id': 'sports_live',
                'name': 'Live Now',
                'extra': [
                  {
                    'name': 'genre',
                    'options': ['Football', 'Basketball'],
                  }
                ],
              }
            ],
          }));
          break;
        case '/catalog/tv/sports_live/genre=Football.json':
          request.response.write(jsonEncode({
            'metas': [
              {
                'id': 'event-1',
                'type': 'tv',
                'name': 'LIVE: Team A vs Team B',
                'genres': ['Football'],
                'description': 'LIVE NOW',
              }
            ],
          }));
          break;
        case '/stream/tv/event-1.json':
          request.response.write(jsonEncode({
            'streams': [
              {
                'name': 'Latino 1080p',
                'url': 'https://example.com/live.m3u8',
              }
            ],
          }));
          break;
        default:
          request.response.statusCode = HttpStatus.notFound;
      }

      await request.response.close();
    });

    SharedPreferences.setMockInitialValues({
      'potv_stremio_addons': jsonEncode([
        {
          'id': 'sports.test',
          'name': 'Sports Test',
          'manifest_uri':
              'http://127.0.0.1:${server.port}/manifest.json',
          'enabled': true,
        }
      ]),
    });

    final repository = AddonSportsRepository(
      const StremioAddonRepository(),
      Dio(),
    );

    final items = await repository.itemsForSport('Soccer');
    expect(items, hasLength(1));
    expect(items.first.name, contains('Team A'));
    expect(items.first.isLive, isTrue);

    final streams = await repository.streamsFor(items.first);
    expect(streams, hasLength(1));
    expect(streams.first.uri.toString(), 'https://example.com/live.m3u8');
    expect(streams.first.language, 'es-MX');
    expect(streams.first.quality, '1080p');
  });
}
