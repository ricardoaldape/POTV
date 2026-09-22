import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../domain/models/sports_event.dart';

final sportsRepositoryProvider = Provider<SportsRepository>((ref) {
  return SportsRepository(Dio());
});

final sportsEventsProvider = FutureProvider.autoDispose
    .family<List<SportsEvent>, ({DateTime day, String? sport})>(
        (ref, query) async {
  return ref.read(sportsRepositoryProvider).eventsForDay(
        query.day,
        sport: query.sport,
      );
});

class SportsRepository {
  static const _apiKey = String.fromEnvironment(
    'SPORTSDB_API_KEY',
    defaultValue: '123',
  );

  final Dio _dio;
  final Map<String, List<SportsEvent>> _cache = {};

  SportsRepository(this._dio);

  Future<List<SportsEvent>> eventsForDay(
    DateTime day, {
    String? sport,
  }) async {
    final date = DateFormat('yyyy-MM-dd').format(day);
    final normalizedSport = sport?.trim() ?? '';
    final cacheKey = '$date|$normalizedSport';
    final cached = _cache[cacheKey];
    if (cached != null) return cached;

    final query = <String, String>{'d': date};
    if (normalizedSport.isNotEmpty) query['s'] = normalizedSport;

    final uri = Uri.https(
      'www.thesportsdb.com',
      '/api/v1/json/$_apiKey/eventsday.php',
      query,
    );

    final response = await _dio.getUri<Map<String, dynamic>>(uri);
    final rawEvents = response.data?['events'];
    if (rawEvents is! List) return const [];

    final events = <SportsEvent>[];
    for (final item in rawEvents) {
      if (item is! Map<String, dynamic>) continue;
      final mapped = _mapEvent(item);
      if (mapped != null) events.add(mapped);
    }

    events.sort((a, b) => a.startsAt.compareTo(b.startsAt));
    _cache[cacheKey] = List.unmodifiable(events);
    return _cache[cacheKey]!;
  }

  SportsEvent? _mapEvent(Map<String, dynamic> raw) {
    final id = _text(raw['idEvent']);
    final home = _text(raw['strHomeTeam']);
    final away = _text(raw['strAwayTeam']);
    if (id == null || home == null || away == null) return null;

    final status = _text(raw['strStatus'])?.toLowerCase() ?? '';
    return SportsEvent(
      id: id,
      sport: _text(raw['strSport']) ?? 'Deporte',
      competition: _text(raw['strLeague']) ?? 'Evento',
      home: home,
      away: away,
      startsAt: _parseStart(raw),
      isLive: status.contains('live') ||
          status.contains('progress') ||
          status.contains('playing'),
    );
  }

  DateTime _parseStart(Map<String, dynamic> raw) {
    final timestamp = _text(raw['strTimestamp']);
    final parsedTimestamp =
        timestamp == null ? null : DateTime.tryParse(timestamp);
    if (parsedTimestamp != null) return parsedTimestamp.toLocal();

    final date = _text(raw['dateEvent']);
    final time = _text(raw['strTime']) ?? '00:00:00';
    final parsed = date == null ? null : DateTime.tryParse('${date}T$time');
    return parsed?.toLocal() ?? DateTime.now();
  }

  String? _text(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
}
