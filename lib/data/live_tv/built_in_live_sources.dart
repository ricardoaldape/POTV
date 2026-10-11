import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/live_channel.dart';
import '../../domain/models/stream_candidate.dart';
import 'm3u_parser.dart';

final builtInLiveSourceRegistryProvider =
    Provider<BuiltInLiveSourceRegistry>((ref) {
  return BuiltInLiveSourceRegistry(Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 18),
      headers: const {
        'User-Agent': 'POTV/0.1 (Android)',
        'Accept': 'application/x-mpegURL,text/plain,*/*',
      },
    ),
  ));
});

final builtInMexicoChannelsProvider =
    FutureProvider.autoDispose<List<LiveChannel>>((ref) {
  return ref.read(builtInLiveSourceRegistryProvider).mexico();
});

final builtInSportsChannelsProvider =
    FutureProvider.autoDispose<List<LiveChannel>>((ref) {
  return ref.read(builtInLiveSourceRegistryProvider).sports();
});

class BuiltInLiveSourceRegistry {
  static const _dearbulutMexico =
      'https://dearbulut.github.io/iptv/playlists/country/mx.m3u';
  static const _dearbulutSports =
      'https://dearbulut.github.io/iptv/playlists/category/sports.m3u';

  static const _iptvOrgMexico =
      'https://iptv-org.github.io/iptv/countries/mx.m3u';
  static const _iptvOrgSports =
      'https://iptv-org.github.io/iptv/categories/sports.m3u';

  final Dio _dio;

  BuiltInLiveSourceRegistry(this._dio);

  Future<List<LiveChannel>> mexico() async {
    final channels = _dedupe([
      ..._starterMexico(),
      ...await _loadMerged([
        _dearbulutMexico,
        _iptvOrgMexico,
      ]),
    ]);
    channels.sort((a, b) {
      final score = _mexicoPriority(b).compareTo(_mexicoPriority(a));
      if (score != 0) return score;
      return a.name.compareTo(b.name);
    });
    return channels;
  }

  Future<List<LiveChannel>> sports() async {
    final channels = _dedupe([
      ..._starterSports(),
      ...await _loadMerged([
        _dearbulutSports,
        _iptvOrgSports,
      ]),
    ]);
    channels.sort((a, b) {
      final score = _sportsPriority(b).compareTo(_sportsPriority(a));
      if (score != 0) return score;
      return a.name.compareTo(b.name);
    });
    return channels;
  }

  List<LiveChannel> _starterMexico() => [
        _channel(
          id: 'potv-mx-adn40',
          name: 'ADN 40',
          group: 'México · Noticias',
          epgId: 'ADN40.mx',
          url:
              'https://mdstrm.com/live-stream-playlist/60b578b060947317de7b57ac.m3u8',
        ),
        _channel(
          id: 'potv-mx-canal22',
          name: 'Canal 22',
          group: 'México · Cultura',
          epgId: 'Canal22.mx',
          url:
              'https://5e50264bd6766.streamlock.net/canal22/smil:canal22.smil/playlist.m3u8',
        ),
        _channel(
          id: 'potv-mx-tv4-43',
          name: 'TV Cuatro 4.3',
          group: 'México · Deportes',
          epgId: 'TV4.3.mx',
          url:
              'https://5ca3e84a76d30.streamlock.net/tv43gto/tv43gto.smil/.m3u8',
        ),
      ];

  List<LiveChannel> _starterSports() => [
        _channel(
          id: 'potv-sport-fifa-hispanic',
          name: 'FIFA+ Hispanic America',
          group: 'Deportes · Fútbol',
          url:
              'https://6c849fb3.wurl.com/master/f36d25e7e52f1ba8d7e56eb859c636563214f541/TEctbXhfRklGQVBsdXNTcGFuaXNoLTFfSExT/playlist.m3u8',
        ),
        _channel(
          id: 'potv-sport-redbull-es',
          name: 'Red Bull TV ES',
          group: 'Deportes',
          url:
              'https://886bd3fbc782459f8de7555d32d7e9ce.mediatailor.us-west-2.amazonaws.com/v1/master/ba62fe743df0fe93366eba3a257d792884136c7f/LINEAR-957-WORBLATAMESFAST-WHALETVPLUS/957/whaletvplus/hls/master/playlist.m3u8',
        ),
        _channel(
          id: 'potv-sport-tv4-43',
          name: 'TV Cuatro 4.3',
          group: 'México · Deportes',
          epgId: 'TV4.3.mx',
          url:
              'https://5ca3e84a76d30.streamlock.net/tv43gto/tv43gto.smil/.m3u8',
        ),
      ];

  LiveChannel _channel({
    required String id,
    required String name,
    required String group,
    String? epgId,
    required String url,
  }) {
    final uri = Uri.parse(url);
    return LiveChannel(
      id: id,
      name: name,
      group: group,
      epgId: epgId,
      stream: StreamCandidate(
        id: '$id:stream',
        label: name,
        uri: uri,
        backend: PlaybackBackend.native,
      ),
    );
  }

  Future<List<LiveChannel>> _loadMerged(List<String> urls) async {
    final results = await Future.wait([
      for (final url in urls) _tryLoad(url),
    ]);

    return _dedupe([
      for (final channels in results) ...channels,
    ]);
  }

  Future<List<LiveChannel>> _tryLoad(String url) async {
    try {
      final response = await _dio.get<String>(
        url,
        options: Options(responseType: ResponseType.plain),
      );
      final raw = response.data ?? '';
      if (raw.trim().isEmpty) return const [];

      return M3uParser.parse(raw)
          .where(_isBuiltInAllowed)
          .toList(growable: false);
    } on DioException {
      return const [];
    }
  }

  bool _isBuiltInAllowed(LiveChannel channel) {
    if (!_isSafePublicStream(channel.stream.uri)) return false;

    final name = channel.name.toLowerCase();
    const excluded = <String>[
      'hbo',
      'cinemax',
      'disney channel',
      'disney jr',
      'espn',
      'fox sports',
      'fox deportes',
      'bein sports',
      'sky sports',
      'dazn',
      'tnt sports',
      'movistar deportes',
      'tudn',
      'geo-blocked',
      'geoblocked',
      'geo blocked',
      'national geographic',
      'comedy central',
      'axn',
    ];

    return !excluded.any(name.contains);
  }

  int _mexicoPriority(LiveChannel channel) {
    final name = channel.name.toLowerCase();
    const preferred = <String, int>{
      'azteca uno': 100,
      'azteca 7': 98,
      'canal 5': 96,
      'las estrellas': 94,
      'imagen tv': 92,
      'adn 40': 90,
      'milenio': 88,
      'canal 22': 84,
      'capital 21': 82,
      'tv unam': 80,
      'mexiquense': 78,
      'jalisco tv': 76,
    };

    var score = 0;
    for (final entry in preferred.entries) {
      if (name.contains(entry.key)) score = entry.value;
    }
    return score;
  }

  int _sportsPriority(LiveChannel channel) {
    final name = channel.name.toLowerCase();
    const preferred = <String, int>{
      'fifa+ hispanic': 110,
      'fifa+': 106,
      'red bull tv es': 104,
      'red bull tv': 100,
      'azteca deportes': 98,
      'claro sports': 96,
      'itv deportes': 92,
      'pluto tv deportes': 90,
      'tv cuatro 4.3': 86,
      'onefootball': 84,
    };

    var score = 0;
    for (final entry in preferred.entries) {
      if (name.contains(entry.key)) score = entry.value;
    }
    if (name.contains('hispanic') || name.contains('españ')) score += 8;
    return score;
  }

  bool _isSafePublicStream(Uri uri) {
    if (uri.scheme != 'https') return false;

    final host = uri.host.toLowerCase();
    if (host.isEmpty ||
        host == 'localhost' ||
        host == '0.0.0.0' ||
        host == '::1' ||
        host == 'jmp2.uk') {
      return false;
    }

    final ipv4 = host.split('.');
    if (ipv4.length == 4 && ipv4.every((part) => int.tryParse(part) != null)) {
      final octets = ipv4.map(int.parse).toList(growable: false);
      if (octets[0] == 10 ||
          octets[0] == 127 ||
          (octets[0] == 169 && octets[1] == 254) ||
          (octets[0] == 172 && octets[1] >= 16 && octets[1] <= 31) ||
          (octets[0] == 192 && octets[1] == 168)) {
        return false;
      }
    }

    return true;
  }

  List<LiveChannel> _dedupe(List<LiveChannel> channels) {
    final seen = <String>{};
    final result = <LiveChannel>[];

    for (final channel in channels) {
      final epg = channel.epgId?.trim().toLowerCase() ?? '';
      final name = channel.name.trim().toLowerCase();
      final key = epg.isNotEmpty ? 'epg:$epg' : 'name:$name';

      if (seen.add(key)) result.add(channel);
    }

    result.sort((a, b) => a.name.compareTo(b.name));
    return result;
  }
}
