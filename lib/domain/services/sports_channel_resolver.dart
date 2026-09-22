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
    final windowStart = event.startsAt.subtract(const Duration(hours: 2));
    final windowEnd = event.startsAt.add(const Duration(hours: 4));
    final eventTokens = _tokens(
      '${event.home} ${event.away} ${event.competition}',
    );

    final matches = <SportsChannelMatch>[];

    for (final channel in channels) {
      EpgProgram? bestProgram;
      var bestScore = _scoreText(channel.name, eventTokens);

      for (final program in programs) {
        if (!_sameChannel(channel, program)) continue;
        if (program.endsAt.isBefore(windowStart)) continue;
        if (program.startsAt.isAfter(windowEnd)) continue;

        final score = _scoreText(program.title, eventTokens) +
            _scoreText(program.description ?? '', eventTokens);

        if (score > bestScore) {
          bestScore = score;
          bestProgram = program;
        }
      }

      if (bestScore >= 4) {
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

  bool _sameChannel(LiveChannel channel, EpgProgram program) {
    if (channel.epgId != null && channel.epgId!.isNotEmpty) {
      return channel.epgId == program.channelId;
    }
    return _normalize(channel.name) == _normalize(program.channelId);
  }

  int _scoreText(String text, Set<String> tokens) {
    final normalized = _normalize(text);
    var score = 0;
    for (final token in tokens) {
      if (normalized.contains(token)) score += token.length >= 6 ? 3 : 2;
    }
    return score;
  }

  Set<String> _tokens(String value) {
    return _normalize(value)
        .split(RegExp(r'[^a-z0-9áéíóúüñ]+'))
        .where((token) => token.length >= 4)
        .where((token) => !_stopWords.contains(token))
        .toSet();
  }

  String _normalize(String value) => value.toLowerCase().trim();

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
