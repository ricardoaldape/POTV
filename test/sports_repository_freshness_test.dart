import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:potv/data/sports/sports_repository.dart';

void main() {
  Map<String, dynamic> fixture({
    String id = 'fixture-1',
    String? timestamp = '2026-10-29T19:00:00Z',
    String? date,
    String? time,
    String status = 'Not Started',
  }) =>
      <String, dynamic>{
        'idEvent': id,
        'strHomeTeam': 'Chiefs',
        'strAwayTeam': 'Bills',
        'strLeague': 'NFL',
        'strStatus': status,
        if (timestamp != null) 'strTimestamp': timestamp,
        if (date != null) 'dateEvent': date,
        if (time != null) 'strTime': time,
      };

  test('never invents a start time for incomplete fixtures', () async {
    final dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      handler.resolve(Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: {
          'events': [
            fixture(id: 'missing', timestamp: null),
            fixture(id: 'invalid', timestamp: 'bad date'),
            fixture(id: 'valid'),
            fixture(
              id: 'fallback',
              timestamp: null,
              date: '2026-10-29',
              time: '20:15:00',
            ),
          ],
        },
      ));
    }));
    final events = await SportsRepository(dio).eventsForDay(
      DateTime(2026, 10, 29),
    );
    expect(events.map((e) => e.id), containsAll(['valid', 'fallback']));
    expect(events, hasLength(2));
    expect(
      events.singleWhere((e) => e.id == 'fallback').startsAt.toUtc(),
      DateTime.utc(2026, 10, 29, 20, 15),
    );
  });

  test('live fixture status is reloaded after TTL, not cached forever',
      () async {
    var now = DateTime.utc(2026, 10, 29, 18);
    var requests = 0;
    var status = 'Live';
    final dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      requests++;
      handler.resolve(Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: {'events': [fixture(status: status)]},
      ));
    }));
    final repo = SportsRepository(
      dio,
      cacheTtl: const Duration(minutes: 2),
      clock: () => now,
    );
    final day = DateTime(2026, 10, 29);
    expect((await repo.eventsForDay(day)).single.isLive, isTrue);
    status = 'Match Finished';
    now = now.add(const Duration(minutes: 1));
    expect((await repo.eventsForDay(day)).single.isLive, isTrue);
    expect(requests, 1);
    now = now.add(const Duration(minutes: 1));
    expect((await repo.eventsForDay(day)).single.isLive, isFalse);
    expect(requests, 2);
  });

  test('UTC timestamps without a suffix are not treated as local time',
      () async {
    final dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      handler.resolve(Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: {
          'events': [
            fixture(timestamp: '2026-10-29T19:00:00'),
          ],
        },
      ));
    }));
    final events = await SportsRepository(dio).eventsForDay(
      DateTime(2026, 10, 29),
    );
    expect(events.single.startsAt.toUtc(), DateTime.utc(2026, 10, 29, 19));
  });
}
