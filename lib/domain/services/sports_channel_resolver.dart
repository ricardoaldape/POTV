import '../models/epg_program.dart';
import '../models/live_channel.dart';
import '../models/sports_event.dart';

class SportsChannelMatch {
  final LiveChannel channel;
  final EpgProgram? program;
  final int score;

  const SportsChannelMatch({
    required this.channel,
    required this.program,
    required this.score,
  });
}

class SportsChannelResolver {
  const SportsChannelResolver();

  List<SportsChannelMatch> resolve({
    required SportsEvent event,
    required List<LiveChannel> channels,
    required List<EpgProgram> programs,
  }) {
    // Require the scheduled broadcast to start near this fixture, not a replay.
    final windowStart = event.startsAt.subtract(const Duration(minutes: 90));
    final windowEnd = event.startsAt.add(const Duration(minutes: 90));
    final eventTokens = _tokens(
      '${event.home} ${event.away} ${event.competition}',
    );

    final matches = <SportsChannelMatch>[];

    // TheSportsDB supplies a fixture, not a watch URL. A channel is linked
    // only when its EPG explicitly mentions BOTH opponents in the right
    // broadcast window; shared sport/league labels are not enough.
    final homeTokens = _orderedTokens(event.home);
    final awayTokens = _orderedTokens(event.away);
    if (homeTokens.isEmpty || awayTokens.isEmpty) return const [];

    // Index EPG once to avoid scanning every programme for every channel.
    final programsByChannel = <String, List<EpgProgram>>{};
    for (final program in programs) {
      final id = _normalize(program.channelId);
      if (id.isNotEmpty) {
        programsByChannel.putIfAbsent(id, () => []).add(program);
      }
    }
    for (final channel in channels) {
      final id = channel.epgId?.trim().isNotEmpty == true
          ? _normalize(channel.epgId!)
          : _normalize(channel.name);
      EpgProgram? bestProgram;
      var bestScore = 0;

      for (final program in programsByChannel[id] ?? const <EpgProgram>[]) {
        if (program.startsAt.isBefore(windowStart) ||
            program.startsAt.isAfter(windowEnd)) {
          continue;
        }
        if (!program.endsAt.isAfter(
          event.startsAt.subtract(const Duration(minutes: 30)),
        )) {
          continue;
        }
        // An EPG replay/highlights entry is not proof of a live fixture,
        // even when its teams and start time match the schedule.
        if (_isReplayTitle(program.title)) continue;
        final summary = '${program.title} ${program.description ?? ''}';
        // Require two distinct, non-overlapping team mentions in one EPG
        // field. "New York City" alone must not also count as "York City".
        final inTitle = _mentionsBothTeams(
          program.title, homeTokens, awayTokens,
        );
        final inDescription = _mentionsBothTeams(
          program.description ?? '', homeTokens, awayTokens,
        );
        if (!inTitle && !inDescription) continue;

        final score = _scoreText(summary, eventTokens);
        if (score > bestScore) {
          bestScore = score;
          bestProgram = program;
        }
      }

      if (bestProgram != null) {
        matches.add(
          SportsChannelMatch(
            channel: channel,
            program: bestProgram,
            score: bestScore,
          ),
        );
      }
    }

    matches.sort((a, b) => b.score.compareTo(a.score));
    return matches;
  }

  bool _mentionsBothTeams(
    String source,
    List<String> home,
    List<String> away,
  ) {
    final words = _orderedTokens(source);
    final homeStarts = _teamStarts(words, home);
    final awayStarts = _teamStarts(words, away);
    for (final h in homeStarts) {
      for (final a in awayStarts) {
        if (h + home.length <= a || a + away.length <= h) return true;
      }
    }
    return false;
  }

  List<int> _teamStarts(List<String> words, List<String> team) {
    if (team.isEmpty || team.length > words.length) return const [];
    final starts = <int>[];
    for (var i = 0; i <= words.length - team.length; i++) {
      var same = true;
      for (var j = 0; j < team.length; j++) {
        if (words[i + j] != team[j]) {
          same = false;
          break;
        }
      }
      if (same) starts.add(i);
    }
    return starts;
  }

  bool _isReplayTitle(String title) {
    final normalized = _normalize(title);
    return RegExp(
      r'\b(replay|repeticion|retransmision|resumen|highlights|recap|diferido)\b',
    ).hasMatch(normalized);
  }

  int _scoreText(String text, Set<String> tokens) {
    final words = _tokens(text);
    var score = 0;
    for (final token in tokens) {
      if (words.contains(token)) score += token.length >= 6 ? 3 : 2;
    }
    return score;
  }

  Set<String> _tokens(String value) => _orderedTokens(value).toSet();

  List<String> _orderedTokens(String value) {
    return _normalize(value)
        .split(RegExp(r'[^a-z0-9]+'))
        .where((token) => token.length >= 4)
        .where((token) => !_stopWords.contains(token))
        .toList(growable: false);
  }

  String _normalize(String value) {
    var normalized = value.toLowerCase().trim();
    const replacements = <String, String>{
      'á': 'a',
      'é': 'e',
      'í': 'i',
      'ó': 'o',
      'ú': 'u',
      'ü': 'u',
      'ñ': 'n',
    };
    for (final entry in replacements.entries) {
      normalized = normalized.replaceAll(entry.key, entry.value);
    }
    return normalized;
  }

  static const _stopWords = <String>{
    'club',
    'team',
    'liga',
    'league',
    'futbol',
    'football',
    'soccer',
    'basket',
  };
}
