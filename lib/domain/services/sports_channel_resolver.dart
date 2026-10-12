import '../models/epg_program.dart';
import '../models/live_channel.dart';
import '../models/sports_event.dart';

class SportsChannelMatch {
  final LiveChannel channel;
  final EpgProgram program;
  final int score;

  const SportsChannelMatch({
    required this.channel,
    required this.program,
    required this.score,
  });
}

/// Never claim a channel is showing an event based on channel branding alone.
///
/// A match requires a channel-linked EPG programme, a programme time window
/// overlapping the match, and *both* participating teams in EPG metadata.
/// When EPG data is missing we deliberately return no playable event match.
class SportsChannelResolver {
  const SportsChannelResolver();

  List<SportsChannelMatch> resolve({
    required SportsEvent event,
    required List<LiveChannel> channels,
    required List<EpgProgram> programs,
  }) {
    final home = _tokens(event.home);
    final away = _tokens(event.away);
    if (home.isEmpty || away.isEmpty) return const [];

    final results = <SportsChannelMatch>[];
    for (final channel in channels) {
      SportsChannelMatch? best;
      for (final program in programs) {
        if (!_sameChannel(channel, program)) continue;
        // Allow a short lead-in while rejecting a totally unrelated programme.
        final leadIn = event.startsAt.subtract(const Duration(minutes: 45));
        final latestStart = event.startsAt.add(const Duration(minutes: 60));
        if (program.endsAt.isBefore(event.startsAt) ||
            program.startsAt.isAfter(latestStart) ||
            program.endsAt.isBefore(leadIn)) {
          continue;
        }
        final info = _tokens('${program.title} ${program.description ?? ''}');
        final homeHits = home.intersection(info).length;
        final awayHits = away.intersection(info).length;
        // Require both teams to be represented, not just the competition.
        if (homeHits == 0 || awayHits == 0) continue;
        final score = 10 + homeHits * 3 + awayHits * 3;
        if (best == null || score > best.score) {
          best = SportsChannelMatch(
            channel: channel,
            program: program,
            score: score,
          );
        }
      }
      if (best != null) results.add(best);
    }
    results.sort((a, b) => b.score.compareTo(a.score));
    return results;
  }

  bool _sameChannel(LiveChannel channel, EpgProgram program) {
    final id = channel.epgId;
    if (id != null && id.trim().isNotEmpty) {
      return _normalize(id) == _normalize(program.channelId);
    }
    return _normalize(channel.name) == _normalize(program.channelId);
  }

  Set<String> _tokens(String value) {
    return _normalize(value)
        .split(RegExp(r'[^a-z0-9]+'))
        .where((token) => token.length >= 4)
        .where((token) => !_stopWords.contains(token))
        .toSet();
  }

  String _normalize(String value) {
    var normalized = value.toLowerCase().trim();
    const replacements = <String, String>{
      'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ü': 'u', 'ñ': 'n',
    };
    for (final entry in replacements.entries) {
      normalized = normalized.replaceAll(entry.key, entry.value);
    }
    return normalized;
  }

  static const _stopWords = <String>{
    'club', 'team', 'liga', 'league', 'futbol', 'football',
    'soccer', 'basket', 'deportivo', 'sporting', 'the',
  };
}
