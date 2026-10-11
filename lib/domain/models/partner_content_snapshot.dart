import 'epg_program.dart';
import 'live_channel.dart';
import 'media_item.dart';
import 'sports_event.dart';
import 'stream_candidate.dart';

/// Transport-neutral content catalog. No partner billing, branding or account
/// models are part of this data contract.
class PartnerContentSnapshot {
  final String revision;
  final DateTime fetchedAt;
  final List<MediaItem> movies;
  final List<MediaItem> series;
  final List<MediaItem> anime;
  final List<LiveChannel> channels;
  final List<LiveChannel> sportsChannels;
  final List<EpgProgram> guidePrograms;
  final List<SportsEvent> sportsEvents;

  const PartnerContentSnapshot({
    required this.revision,
    required this.fetchedAt,
    this.movies = const [],
    this.series = const [],
    this.anime = const [],
    this.channels = const [],
    this.sportsChannels = const [],
    this.guidePrograms = const [],
    this.sportsEvents = const [],
  });

  static PartnerContentSnapshot empty() => PartnerContentSnapshot(
        revision: '',
        fetchedAt: DateTime.fromMillisecondsSinceEpoch(0),
      );

  bool get hasContent =>
      movies.isNotEmpty ||
      series.isNotEmpty ||
      anime.isNotEmpty ||
      channels.isNotEmpty ||
      sportsChannels.isNotEmpty ||
      sportsEvents.isNotEmpty;

  List<MediaItem> forType(MediaType type) => switch (type) {
        MediaType.movie => movies,
        MediaType.tv => series,
        MediaType.anime => anime,
      };

  factory PartnerContentSnapshot.parse(Object? body, {DateTime? fetchedAt}) {
    if (body is! Map) throw const FormatException('Invalid catalog document');
    final document = _map(body);
    final payload = document['data'] is Map ? _map(document['data'] as Map) : document;
    final revision = _text(payload['revision']) ??
        _text(document['revision']) ??
        '';
    final result = PartnerContentSnapshot(
      revision: revision,
      fetchedAt: fetchedAt ?? DateTime.now(),
      movies: _mediaList(payload['movies'], MediaType.movie),
      series: _mediaList(payload['series'] ?? payload['tv'], MediaType.tv),
      anime: _mediaList(payload['anime'], MediaType.anime),
      channels: _channelList(payload['channels'], category: 'tv'),
      guidePrograms: _guideList(payload['now_next'] ??
          payload['nowNext'] ?? payload['epg'] ?? payload['guide']),
      sportsChannels: _channelList(
        payload['sports_channels'] ?? payload['sportsChannels'],
        category: 'sport',
      ),
      sportsEvents: _sportsList(
        payload['sports_events'] ?? payload['sportsEvents'],
      ),
    );
    return result;
  }

  static Map<String, dynamic> _map(Map input) =>
      input.map((key, value) => MapEntry(key.toString(), value));

  static String? _text(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static Uri? _httpsUri(Object? raw) {
    final uri = Uri.tryParse(_text(raw) ?? '');
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return null;
    }
    return uri;
  }

  static List<MediaItem> _mediaList(Object? raw, MediaType type) {
    if (raw is! List) return const [];
    final result = <MediaItem>[];
    final seen = <int>{};
    for (final value in raw) {
      if (value is! Map) continue;
      final item = _map(value);
      // POTV resolves movies/series by TMDB and anime by AniList.
      // Never mistake a provider-specific internal ID for a TMDB ID.
      final id = int.tryParse((type == MediaType.anime
                  ? item['anilist_id'] ?? item['anilistId']
                  : item['tmdb_id'] ?? item['tmdbId'])
              ?.toString() ??
          '');
      final title = _text(item['title'] ?? item['name']);
      if (id == null || id <= 0 || title == null || !seen.add(id)) continue;
      result.add(MediaItem(
        id: id,
        type: type,
        title: title,
        overview: _text(item['overview'] ?? item['description']),
        year: _text(item['year']),
        poster: _httpsUri(item['poster']),
        backdrop: _httpsUri(item['backdrop']),
        externalId: _text(item['imdb_id'] ?? item['external_id']),
        episodeCount: int.tryParse(item['episode_count']?.toString() ?? ''),
      ));
    }
    return List.unmodifiable(result);
  }

  static List<LiveChannel> _channelList(
    Object? raw, {
    required String category,
  }) {
    if (raw is! List) return const [];
    final result = <LiveChannel>[];
    final seen = <String>{};
    for (final value in raw) {
      if (value is! Map) continue;
      final item = _map(value);
      final id = _text(item['id']);
      final name = _text(item['name'] ?? item['title']);
      final url = _httpsUri(
        item['stream_url'] ??
            item['streamUrl'] ??
            item['primary_url'] ??
            item['primaryUrl'] ??
            item['url'],
      );
      if (id == null || name == null || url == null || !seen.add(id)) {
        continue;
      }
      final headers = <String, String>{};
      if (item['headers'] is Map) {
        for (final entry in (item['headers'] as Map).entries) {
          final key = _text(entry.key);
          final headerValue = _text(entry.value);
          if (key != null && headerValue != null) {
            headers[key] = headerValue;
          }
        }
      }
      final backend = item['backend'] == 'webview' ||
              item['is_iframe'] == true
          ? PlaybackBackend.webView
          : PlaybackBackend.native;
      final backups = <StreamCandidate>[];
      final rawBackups = item['backup_urls'] ??
          item['backupUrls'] ??
          item['backups'] ??
          item['alternatives'];
      if (rawBackups is List) {
        final unique = <String>{url.toString()};
        for (var i = 0; i < rawBackups.length; i++) {
          final rawBackup = rawBackups[i];
          final backup = rawBackup is Map ? _map(rawBackup) : null;
          final backupUri = _httpsUri(
            backup == null
                ? rawBackup
                : backup['url'] ??
                    backup['stream_url'] ??
                    backup['streamUrl'],
          );
          if (backupUri == null || !unique.add(backupUri.toString())) {
            continue;
          }
          backups.add(StreamCandidate(
            id: 'partner:$category:$id:backup:${i + 1}',
            label: '$name · respaldo ${i + 1}',
            uri: backupUri,
            backend: backup?['is_iframe'] == true
                ? PlaybackBackend.webView
                : backend,
            headers: headers,
            language: _text(backup?['language']) ?? _text(item['language']),
            quality: _text(backup?['quality']) ?? _text(item['quality']),
          ));
        }
      }
      result.add(LiveChannel(
        id: 'partner:$category:$id',
        name: name,
        group: _text(item['group'] ?? item['category'] ??
            item['genre'] ?? item['group_title']) ??
            (category == 'sport' ? 'Deportes' : null),
        epgId: _text(item['epg_id'] ?? item['epgId']),
        logo: _httpsUri(item['logo']),
        backupStreams: List.unmodifiable(backups),
        stream: StreamCandidate(
          id: 'partner:$category:$id:stream',
          label: name,
          uri: url,
          backend: backend,
          headers: headers,
          language: _text(item['language']),
        ),
      ));
    }
    return List.unmodifiable(result);
  }

  /// Optional normalized guide delivered by the authorized content gateway.
  /// Accept both now/next per channel and a flat list of EPG programs.
  static List<EpgProgram> _guideList(Object? raw) {
    if (raw is! List) return const [];
    final programs = <EpgProgram>[];
    final seen = <String>{};
    void addProgram(Map source, String? defaultChannel) {
      final item = _map(source);
      final channelId = _text(item['channel_id'] ?? item['channelId'] ??
          item['epg_id'] ?? item['epgId'] ?? defaultChannel);
      final title = _text(item['title'] ?? item['name']);
      final start = DateTime.tryParse(
        _text(item['starts_at'] ?? item['startsAt'] ??
            item['start'] ?? item['start_time']) ?? '',
      );
      final end = DateTime.tryParse(
        _text(item['ends_at'] ?? item['endsAt'] ??
            item['end'] ?? item['end_time']) ?? '',
      );
      if (channelId == null || title == null || start == null ||
          end == null || !end.isAfter(start)) return;
      final key = '$channelId|$title|${start.toUtc().toIso8601String()}';
      if (!seen.add(key)) return;
      programs.add(EpgProgram(
        channelId: channelId,
        title: title,
        description: _text(item['description']),
        startsAt: start.toLocal(),
        endsAt: end.toLocal(),
      ));
    }

    for (final value in raw) {
      if (value is! Map) continue;
      final row = _map(value);
      final channelId = _text(row['channel_id'] ?? row['channelId'] ??
          row['epg_id'] ?? row['epgId'] ?? row['channel']);
      final current = row['current'] ?? row['now'];
      final next = row['next'] ?? row['upcoming'];
      if (current is Map || next is Map) {
        if (current is Map) addProgram(current, channelId);
        if (next is Map) addProgram(next, channelId);
      } else {
        addProgram(row, channelId);
      }
    }
    return List.unmodifiable(programs);
  }

  static List<SportsEvent> _sportsList(Object? raw) {
    if (raw is! List) return const [];
    final events = <SportsEvent>[];
    final seen = <String>{};
    for (final value in raw) {
      if (value is! Map) continue;
      final item = _map(value);
      final id = _text(item['id']);
      final home = _text(item['home']);
      final away = _text(item['away']);
      final start = DateTime.tryParse(
        _text(item['starts_at'] ?? item['startsAt']) ?? '',
      );
      if (id == null || home == null || away == null ||
          start == null || !seen.add(id)) {
        continue;
      }
      events.add(SportsEvent(
        id: 'partner:$id',
        sport: _text(item['sport']) ?? 'Deporte',
        competition: _text(item['competition']) ?? 'Evento',
        home: home,
        away: away,
        startsAt: start.toLocal(),
        isLive: item['is_live'] == true || item['isLive'] == true,
      ));
    }
    return List.unmodifiable(events);
  }
}
