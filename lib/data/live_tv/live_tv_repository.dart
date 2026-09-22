import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/epg_program.dart';
import '../../domain/models/live_channel.dart';
import 'm3u_parser.dart';
import 'xmltv_parser.dart';

final liveTvRepositoryProvider = Provider<LiveTvRepository>((ref) {
  return LiveTvRepository(Dio());
});

final liveChannelsProvider =
    AsyncNotifierProvider<LiveChannelsController, List<LiveChannel>>(
  LiveChannelsController.new,
);

class LiveTvRepository {
  static const _sourceKey = 'live_tv_m3u_url';
  static const _epgSourceKey = 'live_tv_xmltv_url';
  final Dio _dio;

  LiveTvRepository(this._dio);

  Future<String?> sourceUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_sourceKey);
  }

  Future<void> saveSource(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sourceKey, value.trim());
  }

  Future<List<LiveChannel>> loadChannels() async {
    final url = await sourceUrl();
    if (url == null || url.isEmpty) return const [];

    final response = await _dio.get<String>(
      url,
      options: Options(responseType: ResponseType.plain),
    );
    final raw = response.data ?? '';
    final embeddedEpg = M3uParser.epgUri(raw);
    if (embeddedEpg != null) {
      final prefs = await SharedPreferences.getInstance();
      final current = prefs.getString(_epgSourceKey);
      if (current == null || current.isEmpty) {
        await prefs.setString(_epgSourceKey, embeddedEpg.toString());
      }
    }
    return M3uParser.parse(raw);
  }
}

class LiveChannelsController extends AsyncNotifier<List<LiveChannel>> {
  @override
  Future<List<LiveChannel>> build() {
    return ref.read(liveTvRepositoryProvider).loadChannels();
  }

  Future<void> setSource(String url) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(liveTvRepositoryProvider).saveSource(url);
      return ref.read(liveTvRepositoryProvider).loadChannels();
    });
    ref.invalidate(epgProgramsProvider);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(liveTvRepositoryProvider).loadChannels(),
    );
  }
}

// XMLTV/EPG configuration is kept local to the device.

final epgProgramsProvider =
    AsyncNotifierProvider<EpgProgramsController, List<EpgProgram>>(
  EpgProgramsController.new,
);

class EpgProgramsController extends AsyncNotifier<List<EpgProgram>> {
  static const _sourceKey = 'live_tv_xmltv_url';
  final Dio _dio = Dio();

  @override
  Future<List<EpgProgram>> build() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString(_sourceKey);
    if (url == null || url.isEmpty) return const [];
    return _load(url);
  }

  Future<void> setSource(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sourceKey, url.trim());
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _load(url));
  }

  Future<void> refresh() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString(_sourceKey);
    if (url == null || url.isEmpty) {
      state = const AsyncData([]);
      return;
    }
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _load(url));
  }

  Future<List<EpgProgram>> _load(String url) async {
    final response = await _dio.get<String>(
      url,
      options: Options(responseType: ResponseType.plain),
    );
    return XmlTvParser.parse(response.data ?? '');
  }
}
