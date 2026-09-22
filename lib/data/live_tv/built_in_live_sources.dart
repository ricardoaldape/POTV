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
    return _loadWithFallback(
      primary: _dearbulutMexico,
      fallback: _iptvOrgMexico,
    );
  }

  Future<List<LiveChannel>> sports() {
    return _loadWithFallback(
      primary: _dearbulutSports,
      fallback: _iptvOrgSports,
    );
  }

  Future<List<LiveChannel>> _loadWithFallback({
    required String primary,
    required String fallback,
  }) async {
    final primaryChannels = await _tryLoad(primary);
    if (primaryChannels.isNotEmpty) {
      return _dedupe(primaryChannels);
    }

    return _dedupe(await _tryLoad(fallback));
  }

  Future<List<LiveChannel>> _tryLoad(String url) async {
    try {
      final response = await _dio.get<String>(
        url,
        options: Options(responseType: ResponseType.plain),
      );
      final raw = response.data ?? '';
      if (raw.trim().isEmpty) return const [];
      return M3uParser.parse(raw);
    } on DioException {
      return const [];
    }
  }

  List<LiveChannel> _dedupe(List<LiveChannel> channels) {
    final seen = <String>{};
    final result = <LiveChannel>[];

    for (final channel in channels) {
      final key = [
        channel.epgId?.trim().toLowerCase() ?? '',
        channel.name.trim().toLowerCase(),
        channel.stream.uri.toString(),
      ].join('|');

      if (seen.add(key)) result.add(channel);
    }

    return result;
  }
}
