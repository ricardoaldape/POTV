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

final starterSportsChannelsProvider = Provider<List<LiveChannel>>((ref) {
  return ref.read(builtInLiveSourceRegistryProvider).starterSports();
});

class BuiltInLiveSourceRegistry {
  static const _dearbulutMexico =
      'https://dearbulut.github.io/iptv/playlists/country/mx.m3u';
  static const _dearbulutSports =
      'https://dearbulut.github.io/iptv/playlists/category/sports.m3u';

  static const _iptvOrgMexico =
      'https://iptv-org.github.io/iptv/countries/mx.m3u';
  static const _achoMexico =
      'https://www.achoapps.com/listas/mexico3.m3u';

  // Source documents supplied to POTV by the authorized LivSportz partner.
  // The partner has already scoped/cleared these catalogs for POTV, so channel
  // entitlement is inherited from the source list instead of inferred from
  // each brand/name. Credentials/tokens are still never embedded in the APK.
  static const _livSportzAuthorizedSources = <String>[
    _achoMexico,
    'https://bit.ly/_TVMEX',
    'https://tvplayerlatino.com/lista.m3u',
    'https://bit.ly/Lat1N0s',
    'https://bit.ly/_Latinotv',
    'https://bit.ly/_latinovariado',
    'https://bit.ly/VIP-LIST4',
    'https://bit.ly/ListaFluxs',
    'https://bit.ly/ListAlterna',
  ];

  static const _iptvOrgSports =
      'https://iptv-org.github.io/iptv/categories/sports.m3u';

  final Dio _dio;
  List<LiveChannel>? _mexicoCache;
  DateTime? _mexicoCacheAt;

  BuiltInLiveSourceRegistry(this._dio);

  Future<List<LiveChannel>> mexico() async {
    final cached = _mexicoCache;
    final cachedAt = _mexicoCacheAt;
    if (cached != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < const Duration(minutes: 15)) {
      return cached;
    }

    final publicChannels = await _loadMerged([
      _dearbulutMexico,
      _iptvOrgMexico,
    ]);
    final partnerChannels =
        await _loadAuthorizedPartner(_livSportzAuthorizedSources);
    final channels = _dedupe([
      ..._starterMexico(),
      ...publicChannels,
      ...partnerChannels,
    ]);
    channels.sort((a, b) {
      final score = _mexicoPriority(b).compareTo(_mexicoPriority(a));
      if (score != 0) return score;
      return a.name.compareTo(b.name);
    });
    _mexicoCache = List.unmodifiable(channels);
    _mexicoCacheAt = DateTime.now();
    return _mexicoCache!;
  }

  Future<List<LiveChannel>> sports() async {
    final channels = _dedupe([
      ...starterSports(),
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

  List<LiveChannel> starterSports() => [
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

  Future<List<LiveChannel>> _loadAuthorizedPartner(List<String> urls) async {
    final results = await Future.wait([
      for (final url in urls) _tryLoad(url, authorizedLivSportz: true),
    ]);
    return _dedupe([
      for (final channels in results) ...channels,
    ]);
  }

  Future<List<LiveChannel>> _tryLoad(
    String url, {
    bool authorizedLivSportz = false,
  }) async {
    final sourceUri = Uri.tryParse(url);
    if (sourceUri == null ||
        sourceUri.scheme != 'https' ||
        sourceUri.host.isEmpty ||
        sourceUri.userInfo.isNotEmpty ||
        _containsSensitiveQuery(sourceUri)) {
      return const [];
    }
    try {
      final response = await _dio.get<String>(
        url,
        options: Options(responseType: ResponseType.plain),
      );
      final raw = response.data ?? '';
      if (raw.trim().isEmpty) return const [];

      final parsed = M3uParser.parse(raw)
          .map(_cleanDisplayChannel)
          .toList(growable: false);
      return parsed
          .where((channel) => !_isPromotionalEntry(channel))
          .where((channel) => !_isAdultEntry(channel))
          .where(
            authorizedLivSportz
                ? _isAuthorizedLivSportzChannel
                : _isBuiltInAllowed,
          )
          .toList(growable: false);
    } on Object {
      // One malformed, redirected or temporarily unavailable partner list
      // must never take down the rest of the Mexico catalog.
      return const [];
    }
  }

  bool _isAdultEntry(LiveChannel channel) {
    final text = '${channel.name} ${channel.group ?? ''}'
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9+]+'), ' ');
    const blocked = <String>[
      'adultos', 'adulto', 'adult', 'xxx', 'porno', 'porn',
      'pornografia', 'pornografico', 'erotico', 'erotica', 'erotic',
      'desnudos', 'desnudas', 'desnudo', 'nude', 'nudity',
      'sex tv', 'sex channel', 'playboy', 'penthouse', 'hustler',
      'brazzers', 'redlight',
    ];
    if (blocked.any((term) => RegExp('(^| )' + RegExp.escape(term) + r'( |$)')
        .hasMatch(text))) {
      return true;
    }
    final compact = text.replaceAll(' ', '');
    return compact.contains('+18') || compact.contains('18+');
  }

  LiveChannel _cleanDisplayChannel(LiveChannel channel) {
    var name = channel.name.trim();
    name = name.replaceAll(
      RegExp(r'\b(?:https?://)?(?:www\.)?achoapps\.com\b',
          caseSensitive: false),
      '',
    );
    name = name.replaceAll(
      RegExp(r'^\s*(?:mx|mexico|méxico)\s*[|·:\-]+\s*',
          caseSensitive: false),
      '',
    );
    name = name.replaceAll(
      RegExp(r'\s*[|·\-]\s*(?:sd|hd|fhd|uhd|4k|720p|1080p)\s*    final text = channel.name.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    const blocked = <String>[
      'mejor proveedor',
      'proveedor de iptv',
      'iptv premium',
      'mas de 3000 canales',
      'más de 3000 canales',
      'suscripcion iptv',
      'suscripción iptv',
      'contrata iptv',
      'whatsapp',
      'telegram',
      'visita nuestro',
    ];
    return blocked.any(text.contains);
  }

  bool _isAuthorizedLivSportzChannel(LiveChannel channel) {
    if (!_isSafePublicStream(channel.stream.uri)) return false;

    // Do not re-license by channel name. If LivSportz supplied the source list,
    // brands such as ESPN/TUDN/HBO/Disney/AXN/DAZN remain eligible here when
    // delivered through a safe HTTPS source. Credential-bearing or cleartext
    // partner feeds belong behind PartnerContentRepository's HTTPS gateway.
    return true;
  }

  bool _containsSensitiveQuery(Uri uri) {
    const sensitive = <String>{
      'username', 'user', 'password', 'pass', 'token', 'auth',
      'apikey', 'api_key', 'key', 'secret', 'signature', 'sig',
      'hdnea', 'expires', 'session',
    };
    return uri.queryParameters.keys
        .map((key) => key.toLowerCase())
        .any(sensitive.contains);
  }

  bool _isBuiltInAllowed(LiveChannel channel) {
    if (!_isSafePublicStream(channel.stream.uri)) return false;

    final name = channel.name.toLowerCase();
    // This block applies only to anonymous/public built-in playlists.
    // Licensed partner channels are delivered by PartnerContentRepository and
    // are allowed regardless of brand when their entitlement comes from the
    // authorized gateway.
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
      'star channel',
      'fx ',
      'paramount',
      'universal tv',
      'warner',
      'history channel',
      'animal planet',
      'amc',
      'sony channel',
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
    if (uri.userInfo.isNotEmpty) return false;

    if (_containsSensitiveQuery(uri)) return false;

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

  String _canonicalChannelName(String value) {
    var name = value.toLowerCase();
    name = name.replaceAll(
      RegExp(r'\[(?:[^\]]*not\s*24\s*/?\s*7[^\]]*)\]', caseSensitive: false),
      '',
    );
    name = name.replaceAll(
      RegExp(r'\((?:2160|1440|1080|720|576|480|360)p\)', caseSensitive: false),
      '',
    );
    name = name.replaceAll(
      RegExp(r'\|\s*(?:uhd|fhd|hd|sd)\b', caseSensitive: false),
      '',
    );
    name = name.replaceAll(
      RegExp(r'www\.achoapps\.com', caseSensitive: false),
      '',
    );
    name = name.replaceAll(RegExp(r'\s+'), ' ').trim();
    return name;
  }

  List<LiveChannel> _dedupe(List<LiveChannel> channels) {
    final seen = <String>{};
    final result = <LiveChannel>[];

    for (final channel in channels) {
      final rawEpg = channel.epgId?.trim().toLowerCase() ?? '';
      final epg = rawEpg.split('@').first.trim();
      final name = _canonicalChannelName(channel.name);
      final key = epg.isNotEmpty ? 'epg:$epg' : 'name:$name';

      if (seen.add(key)) result.add(channel);
    }

    result.sort((a, b) => a.name.compareTo(b.name));
    return result;
  }
}
,
          caseSensitive: false),
      '',
    );
    name = name.replaceAll(
      RegExp(r'\s*\((?:sd|hd|fhd|uhd|4k|720p|1080p)\)\s*    final text = channel.name.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    const blocked = <String>[
      'mejor proveedor',
      'proveedor de iptv',
      'iptv premium',
      'mas de 3000 canales',
      'más de 3000 canales',
      'suscripcion iptv',
      'suscripción iptv',
      'contrata iptv',
      'whatsapp',
      'telegram',
      'visita nuestro',
    ];
    return blocked.any(text.contains);
  }

  bool _isAuthorizedLivSportzChannel(LiveChannel channel) {
    if (!_isSafePublicStream(channel.stream.uri)) return false;

    // Do not re-license by channel name. If LivSportz supplied the source list,
    // brands such as ESPN/TUDN/HBO/Disney/AXN/DAZN remain eligible here when
    // delivered through a safe HTTPS source. Credential-bearing or cleartext
    // partner feeds belong behind PartnerContentRepository's HTTPS gateway.
    return true;
  }

  bool _containsSensitiveQuery(Uri uri) {
    const sensitive = <String>{
      'username', 'user', 'password', 'pass', 'token', 'auth',
      'apikey', 'api_key', 'key', 'secret', 'signature', 'sig',
      'hdnea', 'expires', 'session',
    };
    return uri.queryParameters.keys
        .map((key) => key.toLowerCase())
        .any(sensitive.contains);
  }

  bool _isBuiltInAllowed(LiveChannel channel) {
    if (!_isSafePublicStream(channel.stream.uri)) return false;

    final name = channel.name.toLowerCase();
    // This block applies only to anonymous/public built-in playlists.
    // Licensed partner channels are delivered by PartnerContentRepository and
    // are allowed regardless of brand when their entitlement comes from the
    // authorized gateway.
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
      'star channel',
      'fx ',
      'paramount',
      'universal tv',
      'warner',
      'history channel',
      'animal planet',
      'amc',
      'sony channel',
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
    if (uri.userInfo.isNotEmpty) return false;

    if (_containsSensitiveQuery(uri)) return false;

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

  String _canonicalChannelName(String value) {
    var name = value.toLowerCase();
    name = name.replaceAll(
      RegExp(r'\[(?:[^\]]*not\s*24\s*/?\s*7[^\]]*)\]', caseSensitive: false),
      '',
    );
    name = name.replaceAll(
      RegExp(r'\((?:2160|1440|1080|720|576|480|360)p\)', caseSensitive: false),
      '',
    );
    name = name.replaceAll(
      RegExp(r'\|\s*(?:uhd|fhd|hd|sd)\b', caseSensitive: false),
      '',
    );
    name = name.replaceAll(
      RegExp(r'www\.achoapps\.com', caseSensitive: false),
      '',
    );
    name = name.replaceAll(RegExp(r'\s+'), ' ').trim();
    return name;
  }

  List<LiveChannel> _dedupe(List<LiveChannel> channels) {
    final seen = <String>{};
    final result = <LiveChannel>[];

    for (final channel in channels) {
      final rawEpg = channel.epgId?.trim().toLowerCase() ?? '';
      final epg = rawEpg.split('@').first.trim();
      final name = _canonicalChannelName(channel.name);
      final key = epg.isNotEmpty ? 'epg:$epg' : 'name:$name';

      if (seen.add(key)) result.add(channel);
    }

    result.sort((a, b) => a.name.compareTo(b.name));
    return result;
  }
}
,
          caseSensitive: false),
      '',
    );
    name = name.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (name.isEmpty) name = channel.name.trim();

    StreamCandidate relabel(StreamCandidate stream) => StreamCandidate(
          id: stream.id,
          label: name,
          uri: stream.uri,
          headers: stream.headers,
          backend: stream.backend,
          language: stream.language,
          quality: stream.quality,
        );

    return LiveChannel(
      id: channel.id,
      name: name,
      group: channel.group,
      epgId: channel.epgId,
      logo: channel.logo,
      stream: relabel(channel.stream),
      backupStreams: [
        for (final stream in channel.backupStreams) relabel(stream),
      ],
    );
  }

  bool _isPromotionalEntry(LiveChannel channel) {
    final text = channel.name.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    const blocked = <String>[
      'mejor proveedor',
      'proveedor de iptv',
      'iptv premium',
      'mas de 3000 canales',
      'más de 3000 canales',
      'suscripcion iptv',
      'suscripción iptv',
      'contrata iptv',
      'whatsapp',
      'telegram',
      'visita nuestro',
    ];
    return blocked.any(text.contains);
  }

  bool _isAuthorizedLivSportzChannel(LiveChannel channel) {
    if (!_isSafePublicStream(channel.stream.uri)) return false;

    // Do not re-license by channel name. If LivSportz supplied the source list,
    // brands such as ESPN/TUDN/HBO/Disney/AXN/DAZN remain eligible here when
    // delivered through a safe HTTPS source. Credential-bearing or cleartext
    // partner feeds belong behind PartnerContentRepository's HTTPS gateway.
    return true;
  }

  bool _containsSensitiveQuery(Uri uri) {
    const sensitive = <String>{
      'username', 'user', 'password', 'pass', 'token', 'auth',
      'apikey', 'api_key', 'key', 'secret', 'signature', 'sig',
      'hdnea', 'expires', 'session',
    };
    return uri.queryParameters.keys
        .map((key) => key.toLowerCase())
        .any(sensitive.contains);
  }

  bool _isBuiltInAllowed(LiveChannel channel) {
    if (!_isSafePublicStream(channel.stream.uri)) return false;

    final name = channel.name.toLowerCase();
    // This block applies only to anonymous/public built-in playlists.
    // Licensed partner channels are delivered by PartnerContentRepository and
    // are allowed regardless of brand when their entitlement comes from the
    // authorized gateway.
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
      'star channel',
      'fx ',
      'paramount',
      'universal tv',
      'warner',
      'history channel',
      'animal planet',
      'amc',
      'sony channel',
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
    if (uri.userInfo.isNotEmpty) return false;

    if (_containsSensitiveQuery(uri)) return false;

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

  String _canonicalChannelName(String value) {
    var name = value.toLowerCase();
    name = name.replaceAll(
      RegExp(r'\[(?:[^\]]*not\s*24\s*/?\s*7[^\]]*)\]', caseSensitive: false),
      '',
    );
    name = name.replaceAll(
      RegExp(r'\((?:2160|1440|1080|720|576|480|360)p\)', caseSensitive: false),
      '',
    );
    name = name.replaceAll(
      RegExp(r'\|\s*(?:uhd|fhd|hd|sd)\b', caseSensitive: false),
      '',
    );
    name = name.replaceAll(
      RegExp(r'www\.achoapps\.com', caseSensitive: false),
      '',
    );
    name = name.replaceAll(RegExp(r'\s+'), ' ').trim();
    return name;
  }

  List<LiveChannel> _dedupe(List<LiveChannel> channels) {
    final seen = <String>{};
    final result = <LiveChannel>[];

    for (final channel in channels) {
      final rawEpg = channel.epgId?.trim().toLowerCase() ?? '';
      final epg = rawEpg.split('@').first.trim();
      final name = _canonicalChannelName(channel.name);
      final key = epg.isNotEmpty ? 'epg:$epg' : 'name:$name';

      if (seen.add(key)) result.add(channel);
    }

    result.sort((a, b) => a.name.compareTo(b.name));
    return result;
  }
}
