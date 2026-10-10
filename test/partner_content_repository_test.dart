import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:potv/data/catalog/partner_content_repository.dart';
import 'package:potv/domain/models/media_item.dart';
import 'package:potv/domain/models/partner_content_snapshot.dart';

void main() {
  test('new films, shows, anime, TV and sports reflect without APK rebuild',
      () async {
    var version = 1;
    final requests = <Uri>[];
    final dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        requests.add(options.uri);
        handler.resolve(Response<Object?>(
          requestOptions: options,
          statusCode: 200,
          headers: Headers.fromMap({
            'etag': ['"rev-$version"'],
          }),
          data: {
            'data': {
              'revision': 'rev-$version',
              'movies': [
                {'tmdb_id': 1, 'title': 'Existing Film'},
                if (version >= 2)
                  {'tmdb_id': 2, 'title': 'New Film'},
              ],
              'series': [
                {'tmdb_id': 33, 'title': 'Current Series'},
              ],
              'anime': [
                {'anilist_id': 44, 'title': 'Current Anime'},
              ],
              'channels': [
                {
                  'id': 'tv-1',
                  'name': 'Channel One',
                  'stream_url': 'https://cdn.example/one.m3u8',
                },
                if (version >= 2)
                  {
                    'id': 'tv-2',
                    'name': 'New Channel',
                    'stream_url': 'https://cdn.example/two.m3u8',
                  },
              ],
              'sports_channels': [
                {
                  'id': 'sport-1',
                  'name': 'Sports One',
                  'stream_url': 'https://cdn.example/sports.m3u8',
                }
              ],
              'sports_events': [
                {
                  'id': 'match-1',
                  'sport': 'Soccer',
                  'competition': 'Fixture',
                  'home': 'Home',
                  'away': 'Away',
                  'starts_at': '2026-10-20T20:00:00Z',
                  'is_live': false,
                }
              ],
            }
          },
        ));
      },
    ));
    final catalog = PartnerContentRepository(
      dio,
      endpoint: Uri.parse('https://potv-gateway.example/content'),
    );
    final first = await catalog.load();
    expect(first.revision, 'rev-1');
    expect(first.movies, hasLength(1));
    expect(first.series, hasLength(1));
    expect(first.anime, hasLength(1));
    expect(first.channels, hasLength(1));
    expect(first.sportsChannels, hasLength(1));
    expect(first.sportsEvents, hasLength(1));

    version = 2;
    final cached = await catalog.load();
    expect(cached.revision, 'rev-1');
    final updated = await catalog.load(forceRefresh: true);
    expect(updated.revision, 'rev-2');
    expect(updated.movies.map((item) => item.title), contains('New Film'));
    expect(updated.channels.map((channel) => channel.name),
        contains('New Channel'));
    expect(updated.forType(MediaType.anime).single.id, 44);
    expect(requests, hasLength(2));
  });

  test('validates media identities and ignores partner-only IDs', () async {
    final response = {
      'revision': 'v3',
      'movies': [
        {'id': 123, 'title': 'Unmapped partner id'},
        {'tmdb_id': 22, 'title': 'Mapped movie'},
        {'tmdb_id': 22, 'title': 'Duplicate'},
      ],
      'anime': [
        {'tmdb_id': 66, 'title': 'Wrong ID namespace'},
        {'anilist_id': 99, 'title': 'Correct anime id'},
      ],
      'channels': [
        {'id': 'bad', 'name': 'Non-HTTPS', 'url': 'http://private.example/file'},
        {'id': 'ok', 'name': 'Good', 'url': 'https://cdn.example/live'},
      ],
    };
    final snapshot = PartnerContentSnapshot.parse(response);
    expect(snapshot.movies, hasLength(1));
    expect(snapshot.movies.single.id, 22);
    expect(snapshot.anime.single.id, 99);
    expect(snapshot.channels.single.name, 'Good');
  });

  test('retains last-known snapshot while partner gateway is offline',
      () async {
    var offline = false;
    final dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      if (offline) {
        handler.reject(DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        ));
        return;
      }
      handler.resolve(Response<Object?>(
        requestOptions: options,
        statusCode: 200,
        data: {
          'revision': 'v1',
          'movies': [
            {'tmdb_id': 22, 'title': 'Cached'}
          ]
        },
      ));
    }));
    final repo = PartnerContentRepository(
      dio,
      endpoint: Uri.parse('https://potv-gateway.example/content'),
    );
    final before = await repo.load();
    offline = true;
    final after = await repo.load(forceRefresh: true);
    expect(after.revision, before.revision);
    expect(after.movies.single.title, 'Cached');
  });

  test('cannot make unconfigured or insecure backend requests', () async {
    final dio = Dio();
    var requests = 0;
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      requests++;
      handler.next(options);
    }));
    final repo = PartnerContentRepository(
      dio,
      endpoint: Uri.parse('http://potv-gateway.example/content'),
    );
    expect(repo.configured, isFalse);
    expect((await repo.load()).hasContent, isFalse);
    expect(requests, 0);
  });
}
