import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/sports_event.dart';

final sportsEventsProvider = Provider<List<SportsEvent>>((ref) {
  final now = DateTime.now();
  return [
    SportsEvent(
      id: 'demo-football-1',
      sport: 'Fútbol',
      competition: 'Demo',
      home: 'Equipo A',
      away: 'Equipo B',
      startsAt: now.add(const Duration(minutes: 35)),
    ),
    SportsEvent(
      id: 'demo-basket-1',
      sport: 'Basket',
      competition: 'Demo',
      home: 'Equipo C',
      away: 'Equipo D',
      startsAt: now.add(const Duration(hours: 2)),
    ),
  ];
});
