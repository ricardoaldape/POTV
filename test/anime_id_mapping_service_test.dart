import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:potv/data/anime/anime_id_mapping_service.dart';

void main() {
  test('maps AniList absolute episode when AniZip already has IMDb/season', () async {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(
            Response<Map<String, dynamic>>(
              requestOptions: options,
              statusCode: 200,
              data: {
                'mappings': {
                  'anilist_id': 21,
                  'imdb_id': 'tt0388629',
                },
                'episodes': {
                  '100': {
                    'seasonNumber': 4,
                    'episodeNumber': 9,
                  },
                },
              },
            ),
          );
        },
      ),
    );

    final mapping = await AnimeIdMappingService(dio).mapEpisode(
      anilistId: 21,
      absoluteEpisode: 100,
      title: 'One Piece',
    );

    expect(mapping, isNotNull);
    expect(mapping!.imdbId, 'tt0388629');
    expect(mapping.season, 4);
    expect(mapping.episode, 9);
    expect(mapping.canUseSeriesProtocol, isTrue);
  });

  test('falls back to Cinemeta for absolute anime episode mapping', () async {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.uri.host == 'api.ani.zip') {
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'mappings': {
                    'anilist_id': 20,
                    'imdb_id': null,
                  },
                  'episodes': {
                    '53': {'episode': '53'},
                  },
                },
              ),
            );
            return;
          }

          if (options.path.contains('/catalog/series/top/search=')) {
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'metas': [
                    {
                      'name': 'Naruto',
                      'id': 'tt0409591',
                      'imdb_id': 'tt0409591',
                    },
                  ],
                },
              ),
            );
            return;
          }

          if (options.path.contains('/meta/series/tt0409591.json')) {
            final videos = <Map<String, dynamic>>[
              for (var i = 1; i <= 52; i++)
                {
                  'season': i <= 35 ? 1 : 2,
                  'episode': i <= 35 ? i : i - 35,
                },
              {
                'season': 2,
                'episode': 18,
                'name': 'Long Time No See: Jiraiya Returns!',
              },
            ];
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'meta': {'videos': videos},
                },
              ),
            );
            return;
          }

          handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.badResponse,
            ),
          );
        },
      ),
    );

    final mapping = await AnimeIdMappingService(dio).mapEpisode(
      anilistId: 20,
      absoluteEpisode: 53,
      title: 'Naruto',
    );

    expect(mapping, isNotNull);
    expect(mapping!.imdbId, 'tt0409591');
    expect(mapping.season, 2);
    expect(mapping.episode, 18);
    expect(mapping.canUseSeriesProtocol, isTrue);
  });

  test('keeps native AniList mapping when no series protocol match exists', () async {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(
            Response<Map<String, dynamic>>(
              requestOptions: options,
              statusCode: 200,
              data: {
                'mappings': {'anilist_id': 999},
                'episodes': {
                  '1': {
                    'seasonNumber': 1,
                    'episodeNumber': 1,
                  },
                },
              },
            ),
          );
        },
      ),
    );

    final mapping = await AnimeIdMappingService(dio).mapEpisode(
      anilistId: 999,
      absoluteEpisode: 1,
    );

    expect(mapping, isNotNull);
    expect(mapping!.imdbId, isNull);
    expect(mapping.canUseSeriesProtocol, isFalse);
  });
}
