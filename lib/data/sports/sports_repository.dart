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
  final Duration cacheTtl;
  final DateTime Function() _now;
  final Map<String, ({DateTime fetchedAt, List<SportsEvent> events})>
      _cache = {};

  SportsRepository(
    this._dio, {
    this.cacheTtl = const Duration(minutes: 2),
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  Future<List<SportsEvent>> eventsForDay(
    DateTime day, {
    String? sport,
  }) async {
    final date = DateFormat('yyyy-MM-dd').format(day);
    final normalizedSport = sport?.trim() ?? '';
    final cacheKey = '$date|$normalizedSport';
    final cached = _cache[cacheKey];
    if (cached != null &&
        _now().difference(cached.fetchedAt) < cacheTtl) {
      return cached.events;
    }

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

    events.sort((a, b) {
      final score = _eventPriority(b).compareTo(_eventPriority(a));
      if (score != 0) return score;
      return a.startsAt.compareTo(b.startsAt);
    });
    final result = List<SportsEvent>.unmodifiable(events);
    _cache[cacheKey] = (fetchedAt: _now(), events: result);
    return result;
  }

  int _eventPriority(SportsEvent event) {
    var score = event.isLive ? 100 : 0;
    final text = '${event.competition} ${event.home} ${event.away}'
        .toLowerCase();

    const priorityTerms = <String, int>{
      'liga mx': 40,
      'champions': 36,
      'premier league': 34,
      'la liga': 32,
      'serie a': 28,
      'bundesliga': 28,
      'mls': 24,
      'copa libertadores': 30,
      'concacaf': 30,
      'nfl': 28,
      'nba': 28,
      'formula 1': 28,
      'ufc': 26,
    };

    for (final entry in priorityTerms.entries) {
      if (text.contains(entry.key)) score += entry.value;
    }
    return score;
  }

  SportsEvent? _mapEvent(Map<String, dynamic> raw) {
    final id = _text(raw['idEvent']);
    final home = _text(raw['strHomeTeam']);
    final away = _text(raw['strAwayTeam']);
    if (id == null || home == null || away == null) return null;

    final startsAt = _parseStart(raw);
    // Never invent a fixture start time when the schedule is incomplete.
    if (startsAt == null) return null;
    final status = _text(raw['strStatus'])?.toLowerCase() ?? '';
    return SportsEvent(
      id: id,
      sport: _text(raw['strSport']) ?? 'Deporte',
      competition: _text(raw['strLeague']) ?? 'Evento',
      home: home,
      away: away,
      startsAt: startsAt,
      isLive: status.contains('live') ||
          status.contains('progress') ||
          status.contains('playing'),
    );
  }

  DateTime? _parseStart(Map<String, dynamic> raw) {
    final timestamp = _text(raw['strTimestamp']);
    if (timestamp != null) {
      // TheSportsDB timestamps are UTC; do not interpret an unzoned value
      // in the viewer's timezone.
      final utcTimestamp = RegExp(r'(Z|[+-]\d{2}:?\d{2})$',
              caseSensitive: false)
          .hasMatch(timestamp)
          ? timestamp
          : '${timestamp}Z';
      final parsed = DateTime.tryParse(utcTimestamp);
      if (parsed != null) return parsed.toLocal();
    }

    final date = _text(raw['dateEvent']);
    final time = _text(raw['strTime']);
    if (date == null || time == null) return null;
    // dateEvent + strTime are UTC as documented by TheSportsDB.
    return DateTime.tryParse('${date}T${time}Z')?.toLocal();
  }

  String? _text(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
}
