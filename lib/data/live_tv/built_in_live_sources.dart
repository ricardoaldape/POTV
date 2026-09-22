import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/live_channel.dart';
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

  Future<List<LiveChannel>> mexico() {
    return _loadMerged([
      _dearbulutMexico,
      _iptvOrgMexico,
    ]);
  }

  Future<List<LiveChannel>> sports() {
    return _loadMerged([
      _dearbulutSports,
      _iptvOrgSports,
    ]);
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
          .where((channel) => _isSafePublicStream(channel.stream.uri))
          .toList(growable: false);
    } on DioException {
      return const [];
    }
  }

  bool _isSafePublicStream(Uri uri) {
    if (uri.scheme != 'http' && uri.scheme != 'https') return false;

    final host = uri.host.toLowerCase();
    if (host.isEmpty ||
        host == 'localhost' ||
        host == '0.0.0.0' ||
        host == '::1') {
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
