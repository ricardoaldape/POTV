class SportsEvent {
  final String id;
  final String sport;
  final String competition;
  final String home;
  final String away;
  final DateTime startsAt;
  final bool isLive;

  const SportsEvent({
    required this.id,
    required this.sport,
    required this.competition,
    required this.home,
    required this.away,
    required this.startsAt,
    this.isLive = false,
  });

  String get title => '$home vs $away';
}
