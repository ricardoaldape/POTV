import '../models/epg_program.dart';
import '../models/live_channel.dart';
import '../models/stream_candidate.dart';
import 'sports_hub_organizer.dart';

enum LiveTvCategory {
  all,
  regional,
  news,
  sports,
  entertainment,
  movies,
  kids,
  music,
  documentary,
  culture,
  lifestyle,
  international,
  other,
}

extension LiveTvCategoryInfo on LiveTvCategory {
  String get label => switch (this) {
        LiveTvCategory.all => 'Todos',
        LiveTvCategory.sports => 'Deportes',
        LiveTvCategory.news => 'Noticias',
        LiveTvCategory.movies => 'Cine y series',
        LiveTvCategory.entertainment => 'Entretenimiento',
        LiveTvCategory.kids => 'Infantil',
        LiveTvCategory.music => 'Música',
        LiveTvCategory.documentary => 'Documentales',
        LiveTvCategory.culture => 'Cultura',
        LiveTvCategory.lifestyle => 'Estilo de vida',
        LiveTvCategory.regional => 'Regional',
        LiveTvCategory.international => 'Internacional',
        LiveTvCategory.other => 'Otros',
      };
}

/// Stable program guide lookup shared by cards and channel search. A program
/// belongs to a channel by EPG id or by its name; timestamps are source data,
/// not a claim that the video stream is available or currently playing.
class LiveTvGuide {
  final Map<String, List<EpgProgram>> _byChannel = {};

  LiveTvGuide(Iterable<EpgProgram> programs) {
    for (final program in programs) {
      final key = LiveTvOrganizer.normalize(program.channelId);
      if (key.isNotEmpty) {
        _byChannel.putIfAbsent(key, () => []).add(program);
      }
    }
    for (final list in _byChannel.values) {
      list.sort((a, b) => a.startsAt.compareTo(b.startsAt));
    }
  }

  List<EpgProgram> _programs(LiveChannel channel) {
    final epg = LiveTvOrganizer.normalize(channel.epgId ?? '');
    final name = LiveTvOrganizer.normalize(channel.name);
    if (epg.isNotEmpty && _byChannel.containsKey(epg)) {
      return _byChannel[epg]!;
    }
    return _byChannel[name] ?? const [];
  }

  EpgProgram? onAir(LiveChannel channel, DateTime now) {
    for (final p in _programs(channel)) {
      if (p.isOnAir(now)) return p;
    }
    return null;
  }

  EpgProgram? upNext(LiveChannel channel, DateTime now) {
    for (final p in _programs(channel)) {
      if (p.startsAt.isAfter(now)) return p;
    }
    return null;
  }
}

/// Vendor-neutral channel classification and source merging. All channel
/// sources remain owned by POTV or independently configured by the user.
class LiveTvOrganizer {
  const LiveTvOrganizer();

  static String normalize(String text) {
    var s = text.toLowerCase().trim();
    const replacements = {
      'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o',
      'ú': 'u', 'ü': 'u', 'ñ': 'n',
    };
    for (final e in replacements.entries) {
      s = s.replaceAll(e.key, e.value);
    }
    return s.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  }

  static bool _containsAny(String text, Iterable<String> terms) {
    final value = ' ${normalize(text)} ';
    return terms.any((term) => value.contains(' $term '));
  }

  bool isAllowedChannel(LiveChannel channel) {
    final raw = '${channel.name} ${channel.group ?? ''}'.toLowerCase();
    if (RegExp(r'(^|[^0-9])(?:18\+|\+18)([^0-9]|$)').hasMatch(raw)) {
      return false;
    }
    final text = normalize(raw);
    final padded = ' $text ';
    const blocked = <String>[
      'adultos', 'adulto', 'adult', 'xxx', 'porno', 'porn',
      'pornografia', 'pornografico', 'pornografica',
      'erotico', 'eroticos', 'erotica', 'eroticas', 'erotic',
      'desnudos', 'desnudas', 'desnudo', 'nude', 'nudity',
      'sex tv', 'sex channel', 'playboy', 'penthouse', 'hustler',
      'brazzers', 'redlight',
    ];
    if (blocked.any((term) => padded.contains(' $term '))) return false;
    return true;
  }

  LiveTvCategory categoryFor(LiveChannel channel) {
    final group = normalize(channel.group ?? '');
    final name = normalize(channel.name);
    final text = '$group $name';
    // The same sports classifier drives Sports Hub and Live TV, including
    // channels in general-category M3U playlists.
    if (const SportsHubOrganizer().isSportsChannel(channel)) {
      return LiveTvCategory.sports;
    }
    if (_containsAny(text, const [
      'regional', 'local', 'estatal', 'municipal',
      'aguascalientes', 'baja california', 'campeche', 'chiapas',
      'chihuahua', 'coahuila', 'colima', 'durango', 'guanajuato',
      'guerrero', 'hidalgo', 'jalisco', 'michoacan', 'morelos',
      'nayarit', 'nuevo leon', 'oaxaca', 'puebla', 'queretaro',
      'quintana roo', 'san luis', 'sinaloa', 'sonora', 'tabasco',
      'tamaulipas', 'tlaxcala', 'veracruz', 'yucatan', 'zacatecas',
      'monterrey', 'saltillo', 'laguna', 'chetumal', 'guadalajara',
      'mexiquense', 'edomex', 'capital 21', 'cdmx',
      'cozumel', 'cancun', 'cancún', 'merida', 'merida yucatan',
      'leon guanajuato', 'tepic', 'toluca', 'cuernavaca',
      'acapulco', 'tuxtla', 'villahermosa', 'hermosillo',
      'culiacan', 'culiacán', 'torreon', 'torreón', 'juarez', 'juárez',
    ])) return LiveTvCategory.regional;
    if (_containsAny(text, const [
      'news', 'noticias', 'informativo', 'informativos', 'noticiero',
      'cnn', 'adn 40', 'milenio', 'bbc news', 'dw espanol',
    ])) return LiveTvCategory.news;

    if (_containsAny(text, const [
      'kids', 'kids tv', 'infantil', 'infantiles', 'ninos', 'children',
      'cartoon', 'nickelodeon', 'nick jr', 'disney channel', 'disney jr',
      'disney xd', 'animacion', 'animados', 'baby tv', 'discovery kids',
    ])) return LiveTvCategory.kids;

    if (_containsAny(text, const [
      'cine', 'movies', 'movie', 'peliculas', 'series', 'cinema',
      'film', 'filmes', 'filmoteca', 'axn', 'amc', 'hbo', 'cinemax',
      'sony channel', 'warner channel', 'universal tv', 'star channel',
      'fx', 'tnt', 'paramount channel',
    ])) return LiveTvCategory.movies;

    if (_containsAny(text, const [
      'music', 'musica', 'musical', 'conciertos', 'concerts',
      'mtv', 'radio', 'videoclips',
    ])) return LiveTvCategory.music;

    if (_containsAny(text, const [
      'documentary', 'documentaries', 'documental', 'documentales',
      'nature', 'naturaleza', 'science', 'ciencia', 'historia',
      'history', 'history channel', 'discovery', 'discovery channel',
      'discovery science', 'natgeo', 'nat geo', 'national geographic',
      'animal planet', 'investigation discovery', 'id discovery',
    ])) return LiveTvCategory.documentary;

    if (_containsAny(text, const [
      'cultura', 'cultural', 'culture', 'educacion', 'educativo',
      'education', 'universidad', 'arte', 'arts', 'teatro',
    ])) return LiveTvCategory.culture;

    if (_containsAny(text, const [
      'lifestyle', 'estilo de vida', 'cocina', 'cooking', 'food',
      'viajes', 'travel', 'turismo', 'hogar', 'home', 'moda',
      'fashion', 'bienestar', 'salud', 'religion', 'religioso',
    ])) return LiveTvCategory.lifestyle;

    if (_containsAny(text, const [
      'entertainment', 'entretenimiento', 'variedades',
      'humor', 'comedy', 'reality', 'show', 'shows',
      'las estrellas', 'azteca uno', 'azteca 7', 'canal 5',
      'fox', 'televisa', 'telemundo', 'unicable', 'distrito comedia',
      'e entertainment', 'tlc',
    ])) return LiveTvCategory.entertainment;

    if (_containsAny(group, const [
      'international', 'internacional', 'global', 'world', 'europa',
      'asia', 'africa',
    ])) return LiveTvCategory.international;

    return LiveTvCategory.other;
  }

  LiveChannel _declaredSports(LiveChannel source) {
    // Provider source section is only a hint: explicit news, culture, film
    // or other group metadata must not be overwritten as "Sports".
    if (const SportsHubOrganizer().isSportsChannel(source) ||
        categoryFor(source) != LiveTvCategory.other) return source;
    return LiveChannel(
      id: source.id,
      name: source.name,
      group: 'Deportes' +
          (source.group?.isNotEmpty == true ? ' · ${source.group}' : ''),
      epgId: source.epgId,
      logo: source.logo,
      stream: source.stream,
      backupStreams: source.backupStreams,
    );
  }

  /// Keeps preferred-source order: partner catalog, existing POTV/M3U, sports
  /// feeds. Identical channels consolidate additional candidates as backups.
  /// Conflicting *explicit* EPG identifiers remain separate channels.
  List<LiveChannel> merge({
    required Iterable<LiveChannel> partner,
    required Iterable<LiveChannel> local,
    required Iterable<LiveChannel> partnerSports,
    required Iterable<LiveChannel> publicSports,
  }) {
    final result = <LiveChannel>[];
    final byEpg = <String, int>{};
    final byName = <String, List<int>>{};

    for (final channel in [
      ...partner,
      ...local,
      ...partnerSports.map(_declaredSports),
      ...publicSports.map(_declaredSports),
    ]) {
      if (!isAllowedChannel(channel)) continue;
      final name = normalize(channel.name);
      if (name.isEmpty) continue;
      final epg = normalize(channel.epgId ?? '');
      int? current;
      if (epg.isNotEmpty) current = byEpg[epg];
      if (current == null) {
        for (final i in byName[name] ?? const <int>[]) {
          final existingEpg = normalize(result[i].epgId ?? '');
          if (epg.isEmpty || existingEpg.isEmpty || existingEpg == epg) {
            current = i;
            break;
          }
        }
      }

      if (current == null) {
        final index = result.length;
        result.add(channel);
        if (epg.isNotEmpty) byEpg[epg] = index;
        byName.putIfAbsent(name, () => []).add(index);
        continue;
      }

      final previous = result[current];
      final existing = <String>{};
      final candidates = <StreamCandidate>[];
      for (final candidate in [
        ...previous.playbackCandidates,
        ...channel.playbackCandidates,
      ]) {
        final key = '${candidate.backend.name}|${candidate.uri}|${candidate.headers}';
        if (existing.add(key)) candidates.add(candidate);
      }
      result[current] = LiveChannel(
        id: previous.id,
        name: previous.name,
        group: !const SportsHubOrganizer().isSportsChannel(previous) &&
                const SportsHubOrganizer().isSportsChannel(channel)
            ? channel.group
            : (previous.group?.trim().isNotEmpty ?? false)
                ? previous.group
                : channel.group,
        epgId: previous.epgId ?? channel.epgId,
        logo: previous.logo ?? channel.logo,
        stream: candidates.first,
        backupStreams: List.unmodifiable(candidates.skip(1)),
      );
      final combinedEpg = normalize(result[current].epgId ?? '');
      if (combinedEpg.isNotEmpty) byEpg[combinedEpg] = current;
      if (epg.isNotEmpty) byEpg[epg] = current;
    }
    return List.unmodifiable(result);
  }

  List<LiveChannel> filter(
    Iterable<LiveChannel> channels, {
    required LiveTvCategory category,
    required String search,
    required Set<String> favorites,
    required bool favoritesOnly,
    required LiveTvGuide guide,
    required DateTime now,
  }) {
    final query = normalize(search);
    return channels.where((channel) {
      if (category != LiveTvCategory.all &&
          categoryFor(channel) != category) return false;
      final favKeys = <String>{
        'name:${channel.name.trim().toLowerCase()}',
        if (channel.epgId?.trim().isNotEmpty ?? false)
          'epg:${channel.epgId!.trim()}',
      };
      if (favoritesOnly && !favKeys.any(favorites.contains)) return false;
      if (query.isEmpty) return true;
      final program = guide.onAir(channel, now);
      final next = guide.upNext(channel, now);
      final text = normalize([
        channel.name,
        channel.group ?? '',
        program?.title ?? '',
        next?.title ?? '',
      ].join(' '));
      return text.contains(query);
    }).toList(growable: false);
  }

  Map<LiveTvCategory, int> counts(Iterable<LiveChannel> channels) {
    final result = <LiveTvCategory, int>{for (final c in LiveTvCategory.values) c: 0};
    for (final channel in channels) {
      result[LiveTvCategory.all] = result[LiveTvCategory.all]! + 1;
      final c = categoryFor(channel);
      result[c] = result[c]! + 1;
    }
    return result;
  }
}
