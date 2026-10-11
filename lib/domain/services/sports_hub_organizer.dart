import '../models/live_channel.dart';
import '../models/sports_event.dart';
import '../models/stream_candidate.dart';

/// Shared taxonomy for sports schedules, installed addons and TV sources.
/// Provider-specific English / Spanish sport labels are normalized here,
/// rather than being embedded in every screen.
enum SportsHubCategory {
  all,
  soccer,
  americanFootball,
  basketball,
  baseball,
  combat,
  hockey,
  motorsport,
  tennis,
  other,
  sportsTv,
}

extension SportsHubCategoryInfo on SportsHubCategory {
  String get title => switch (this) {
        SportsHubCategory.all => 'Todos',
        SportsHubCategory.soccer => 'Fútbol',
        SportsHubCategory.americanFootball => 'Americano',
        SportsHubCategory.basketball => 'Básquetbol',
        SportsHubCategory.baseball => 'Béisbol',
        SportsHubCategory.combat => 'Combate',
        SportsHubCategory.hockey => 'Hockey',
        SportsHubCategory.motorsport => 'Motor',
        SportsHubCategory.tennis => 'Tenis',
        SportsHubCategory.other => 'Más deportes',
        SportsHubCategory.sportsTv => 'TV deportiva',
      };

  /// TheSportsDB and addon catalog requests use these canonical names.
  String? get apiSport => switch (this) {
        SportsHubCategory.all ||
        SportsHubCategory.other ||
        SportsHubCategory.sportsTv => null,
        SportsHubCategory.soccer => 'Soccer',
        SportsHubCategory.americanFootball => 'American Football',
        SportsHubCategory.basketball => 'Basketball',
        SportsHubCategory.baseball => 'Baseball',
        SportsHubCategory.combat => 'Fighting',
        SportsHubCategory.hockey => 'Ice Hockey',
        SportsHubCategory.motorsport => 'Motorsport',
        SportsHubCategory.tennis => 'Tennis',
      };

  bool get isTelevision => this == SportsHubCategory.sportsTv;
}

/// Categorizes and merges sport-specific provider channels and user M3U
/// channels, without ever mistaking all live TV for sport programming.
class SportsHubOrganizer {
  const SportsHubOrganizer();

  String normalize(String value) {
    var result = value.toLowerCase().trim();
    const accents = <String, String>{
      'á': 'a',
      'é': 'e',
      'í': 'i',
      'ó': 'o',
      'ú': 'u',
      'ü': 'u',
      'ñ': 'n',
    };
    for (final accent in accents.entries) {
      result = result.replaceAll(accent.key, accent.value);
    }
    return result.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  }

  bool _has(String text, Iterable<String> terms) {
    final padded = ' $text ';
    for (final term in terms) {
      if (padded.contains(' $term ')) return true;
    }
    return false;
  }

  SportsHubCategory classifySport(String value) {
    final text = normalize(value);
    // Order matters: "American football" and "fútbol americano" must not
    // fall into the ordinary soccer/football bucket.
    if (_has(text, const [
      'american football', 'futbol americano', 'nfl', 'ncaa football',
      'gridiron', 'super bowl'
    ])) {
      return SportsHubCategory.americanFootball;
    }
    if (_has(text, const [
      'mma', 'ufc', 'boxing', 'boxeo', 'kickboxing', 'kick boxing',
      'fight', 'fighting', 'combat', 'combate', 'wrestling',
      'lucha libre', 'wwe', 'bellator', 'muay thai'
    ])) {
      return SportsHubCategory.combat;
    }
    if (_has(text, const [
      'soccer', 'football', 'futbol', 'fut', 'fifa',
      'liga mx', 'champions league', 'premier league', 'onefootball'
    ])) {
      return SportsHubCategory.soccer;
    }
    if (_has(text, const ['basketball', 'basket', 'basquetbol', 'baloncesto', 'nba', 'wnba'])) {
      return SportsHubCategory.basketball;
    }
    if (_has(text, const ['baseball', 'beisbol', 'mlb'])) {
      return SportsHubCategory.baseball;
    }
    if (_has(text, const ['ice hockey', 'hockey', 'nhl'])) {
      return SportsHubCategory.hockey;
    }
    if (_has(text, const [
      'motorsport', 'motor', 'formula', 'formula 1', 'f1',
      'nascar', 'motogp', 'racing', 'rally', 'automovilismo'
    ])) {
      return SportsHubCategory.motorsport;
    }
    if (_has(text, const ['tennis', 'tenis', 'atp', 'wta', 'wimbledon'])) {
      return SportsHubCategory.tennis;
    }
    return SportsHubCategory.other;
  }

  SportsHubCategory categoryForEvent(SportsEvent event) {
    final fromSport = classifySport(event.sport);
    return fromSport == SportsHubCategory.other
        ? classifySport(event.competition)
        : fromSport;
  }

  /// A channel with a general sports label is *not* assigned to soccer (etc.)
  /// simply because it may occasionally air matches from that sport.
  SportsHubCategory? categoryForChannel(LiveChannel channel) {
    final group = normalize(channel.group ?? '');
    final name = normalize(channel.name);
    final text = '$name $group';
    if (!_isSportText(text)) return null;

    final category = classifySport(text);
    return category == SportsHubCategory.other ? null : category;
  }

  bool isSportsChannel(LiveChannel channel) {
    final text = normalize('${channel.name} ${channel.group ?? ''}');
    return _isSportText(text);
  }

  bool _isSportText(String text) =>
      classifySport(text) != SportsHubCategory.other ||
      _has(text, const [
        'sports', 'sport', 'deportes', 'deporte',
        'deportiva', 'deportivo', 'athletics'
      ]);

  List<SportsEvent> eventsFor(
    Iterable<SportsEvent> events,
    SportsHubCategory category, {
    required DateTime day,
  }) {
    if (category.isTelevision) return const [];
    final filtered = <SportsEvent>[];
    final seen = <String>{};
    for (final event in events) {
      if (event.startsAt.year != day.year ||
          event.startsAt.month != day.month ||
          event.startsAt.day != day.day) {
        continue;
      }
      final sport = categoryForEvent(event);
      if (category != SportsHubCategory.all && sport != category) continue;
      final key = normalize(
        '${event.sport}|${event.home}|${event.away}|${event.startsAt.toUtc().toIso8601String()}',
      );
      if (seen.add(key)) filtered.add(event);
    }
    filtered.sort((a, b) {
      if (a.isLive != b.isLive) return a.isLive ? -1 : 1;
      return a.startsAt.compareTo(b.startsAt);
    });
    return List.unmodifiable(filtered);
  }

  List<LiveChannel> mergeSportChannels({
    required Iterable<LiveChannel> partnerSports,
    required Iterable<LiveChannel> builtInSports,
    required Iterable<LiveChannel> localChannels,
    required Iterable<LiveChannel> partnerGeneral,
  }) {
    final result = <LiveChannel>[];
    final indices = <String, int>{};
    for (final channel in [
      ...partnerSports,
      ...builtInSports,
      ...localChannels.where(isSportsChannel),
      ...partnerGeneral.where(isSportsChannel),
    ]) {
      final epg = normalize(channel.epgId ?? '');
      final name = normalize(channel.name);
      if (name.isEmpty) continue;
      final key = epg.isNotEmpty ? 'epg:$epg' : 'name:$name';
      final existingIndex = indices[key];
      if (existingIndex == null) {
        indices[key] = result.length;
        result.add(channel);
      } else {
        // Same channel from different playlists: keep a working fallback
        // without duplicating the entire channel tile.
        final current = result[existingIndex];
        final allStreams = <StreamCandidate>[
          ...current.playbackCandidates,
        ];
        final streamIds = allStreams
            .map((s) => '${s.backend}|${s.uri}|${s.headers}')
            .toSet();
        for (final candidate in channel.playbackCandidates) {
          final sourceKey =
              '${candidate.backend}|${candidate.uri}|${candidate.headers}';
          if (streamIds.add(sourceKey)) allStreams.add(candidate);
        }
        result[existingIndex] = LiveChannel(
          id: current.id,
          name: current.name,
          group: current.group ?? channel.group,
          epgId: current.epgId ?? channel.epgId,
          logo: current.logo ?? channel.logo,
          stream: allStreams.first,
          backupStreams: allStreams.skip(1).toList(growable: false),
        );
      }
    }
    return List.unmodifiable(result);
  }

  List<LiveChannel> channelsFor(
    Iterable<LiveChannel> channels,
    SportsHubCategory category, {
    bool generalOnly = false,
  }) {
    if (category == SportsHubCategory.all ||
        category == SportsHubCategory.sportsTv) {
      return channels.toList(growable: false);
    }
    return channels
        .where((channel) {
          final detected = categoryForChannel(channel);
          if (generalOnly) return detected == null;
          return detected == category;
        })
        .toList(growable: false);
  }

  List<LiveChannel> generalChannels(Iterable<LiveChannel> channels) =>
      channels
          .where((channel) => categoryForChannel(channel) == null)
          .toList(growable: false);
}
