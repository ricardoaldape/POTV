import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:potv/data/anime/anime_id_mapping_service.dart';

void main() {
  test('maps an AniList absolute episode to IMDb season and episode', () async {
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
                    'absoluteEpisodeNumber': 100,
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

    final service = AnimeIdMappingService(dio);
    final mapping = await service.mapEpisode(
      anilistId: 21,
      absoluteEpisode: 100,
    );

    expect(mapping, isNotNull);
    expect(mapping!.imdbId, 'tt0388629');
    expect(mapping.season, 4);
    expect(mapping.episode, 9);
    expect(mapping.canUseSeriesProtocol, isTrue);
  });

  test('keeps anime mapping usable for native AniList sources without IMDb',
      () async {
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
                  'anilist_id': 999,
                },
                'episodes': {
                  '1': {
                    'absoluteEpisodeNumber': 1,
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

    final service = AnimeIdMappingService(dio);
    final mapping = await service.mapEpisode(
      anilistId: 999,
      absoluteEpisode: 1,
    );

    expect(mapping, isNotNull);
    expect(mapping!.imdbId, isNull);
    expect(mapping.canUseSeriesProtocol, isFalse);
  });
}
