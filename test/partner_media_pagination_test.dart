import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:potv/data/catalog/partner_content_repository.dart';
import 'package:potv/domain/models/media_item.dart';

void main() {
  test('pages beyond 1500 through first-party private metadata API', () async {
    final calls = <Uri>[];
    final dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      calls.add(options.uri);
      final offset = int.parse(options.uri.queryParameters['offset']!);
      handler.resolve(Response<Object?>(
        requestOptions: options,
        statusCode: 200,
        data: {
          'ok': true,
          'data': {
            'kind': 'movies',
            'revision': 'sync-rev-1',
            'offset': offset,
            'limit': 200,
            'total': 2200,
            'has_more': offset + 200 < 2200,
            'items': [
              {
                'tmdb_id': offset + 1,
                'title': 'Licensed movie',
                'url': 'https://private.example/secret',
                'token': 'never-expose',
              },
            ],
          },
        },
      ));
    }));
    final repo = PartnerContentRepository(
      dio,
      endpoint: Uri.parse('https://potv.fxqubit.com/api/v1/content/catalog'),
    );
    final page = await repo.loadMediaPage(MediaType.movie, offset: 1500);
    expect(page.total, 2200);
    expect(page.revision, 'sync-rev-1');
    expect(page.items.single.id, 1501);
    expect(page.hasMore, isTrue);
    final last = await repo.loadMediaPage(MediaType.movie, offset: 2000);
    expect(last.hasMore, isFalse);
    expect(calls, hasLength(2));
    expect(calls.first.path, '/api/v1/content/media');
    expect(calls.first.queryParameters['kind'], 'movies');
    expect(calls.first.queryParameters['offset'], '1500');
    expect(calls.first.queryParameters['limit'], '200');
    expect(page.items.single.title, 'Licensed movie');
  });

  test('never sends media page requests to untrusted hosts', () async {
    var calls = 0;
    final dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      calls++;
      handler.next(options);
    }));
    final repo = PartnerContentRepository(
      dio,
      endpoint: Uri.parse('https://untrusted.example/catalog'),
    );
    await expectLater(repo.loadMediaPage(MediaType.tv), throwsStateError);
    expect(calls, 0);
  });

  test('invalid pagination fails before network access', () async {
    var calls = 0;
    final dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      calls++;
      handler.next(options);
    }));
    final repo = PartnerContentRepository(
      dio,
      endpoint: Uri.parse('https://potv.fxqubit.com/api/v1/content/catalog'),
    );
    await expectLater(
      repo.loadMediaPage(MediaType.movie, offset: -1),
      throwsRangeError,
    );
    await expectLater(
      repo.loadMediaPage(MediaType.movie, limit: 501),
      throwsRangeError,
    );
    expect(calls, 0);
  });
}
