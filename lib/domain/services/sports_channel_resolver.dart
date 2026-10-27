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
    final homeTokens = _tokens(event.home);
    final awayTokens = _tokens(event.away);
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
        final summary = '${program.title} ${program.description ?? ''}';
        // Both opponents must appear in the same EPG field; combining
        // unrelated title and description can invent a fixture.
        final title = program.title;
        final description = program.description ?? '';
        final inTitle =
            _containsTeam(title, homeTokens) &&
            _containsTeam(title, awayTokens);
        final inDescription =
            _containsTeam(description, homeTokens) &&
            _containsTeam(description, awayTokens);
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

  bool _containsTeam(String source, Set<String> tokens) {
    // Require the team's tokens in order and adjacent. Looking for a set of
    // words across the whole title incorrectly combines "Real" from Real
    // Sociedad with "Madrid" from Atletico Madrid.
    final words = _orderedTokens(source);
    final team = tokens.toList(growable: false);
    if (team.length > words.length) return false;
    for (var i = 0; i <= words.length - team.length; i++) {
      var same = true;
      for (var j = 0; j < team.length; j++) {
        if (words[i + j] != team[j]) {
          same = false;
          break;
        }
      }
      if (same) return true;
    }
    return false;
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
