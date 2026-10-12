import 'stream_candidate.dart';

class SportsEvent {
  final String id;
  final String sport;
  final String competition;
  final String home;
  final String away;
  final DateTime startsAt;
  final bool isLive;
  /// Streams explicitly attached to this exact event by an authorized
  /// partner catalog. Never infer a game's stream from generic TV channels.
  final List<StreamCandidate> streams;

  const SportsEvent({
    required this.id,
    required this.sport,
    required this.competition,
    required this.home,
    required this.away,
    required this.startsAt,
    this.isLive = false,
    this.streams = const [],
  });

  String get title => '$home vs $away';
}
