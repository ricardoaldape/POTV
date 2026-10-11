import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/epg_program.dart';
import '../../domain/models/live_channel.dart';
import '../../domain/services/live_tv_organizer.dart';
import 'built_in_live_sources.dart';
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
  static const _sourcesKey = 'live_tv_m3u_sources_v2';
  static const _maxSources = 25;
  static const _sourceKindKey = 'live_tv_source_kind';
  static const _localPathKey = 'live_tv_local_path';
  static const _epgSourceKey = 'live_tv_xmltv_url';

  final Dio _dio;

  LiveTvRepository(this._dio);

  Future<String?> sourceUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_sourceKey);
  }

  // The previous version of POTV had one playlist slot. Preserve both old
  // URL and imported file on upgrade instead of dropping the user's sources.
  Future<List<String>> _savedKeys(SharedPreferences prefs) async {
    final saved = prefs.getStringList(_sourcesKey);
    if (saved != null) return saved;
    final migrated = <String>[];
    final oldUrl = prefs.getString(_sourceKey)?.trim() ?? '';
    if (oldUrl.isNotEmpty) migrated.add('url:$oldUrl');
    final oldFile = prefs.getString(_localPathKey)?.trim() ?? '';
    if (oldFile.isNotEmpty) migrated.add('file:$oldFile');
    await prefs.setStringList(_sourcesKey, migrated);
    return migrated;
  }

  Future<List<({String key, String label})>> configuredSources() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = await _savedKeys(prefs);
    return [
      for (final key in keys)
        (
          key: key,
          // Never expose private token-bearing source URLs in the UI.
          label: key.startsWith('url:')
              ? (Uri.tryParse(key.substring(4))?.host ?? 'Lista M3U remota')
              : 'Archivo M3U importado',
        ),
    ];
  }

  Future<void> saveSource(String value) async {
    final url = value.trim();
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasAuthority ||
        (uri.scheme != 'https' && uri.scheme != 'http')) {
      throw const FormatException('La lista M3U debe tener una URL HTTP(S) válida.');
    }
    final prefs = await SharedPreferences.getInstance();
    final entries = await _savedKeys(prefs);
    final key = 'url:$url';
    if (entries.contains(key)) return;
    if (entries.length >= _maxSources) {
      throw StateError('Se alcanzó el límite de listas M3U.');
    }
    await prefs.setStringList(_sourcesKey, [...entries, key]);
    // Keep the legacy field for backwards compatibility; do not return to
    // the old single-source mode when another list is added.
    await prefs.setString(_sourceKey, url);
    await prefs.setString(_sourceKindKey, 'url');
  }

  Future<void> saveLocalPlaylist(String raw) async {
    if (!raw.trimLeft().startsWith('#EXTM3U')) {
      throw const FormatException('El archivo no es una lista M3U.');
    }
    if (raw.length > 10 * 1024 * 1024) {
      throw const FormatException('La lista M3U supera 10 MB.');
    }
    final dir = await getApplicationSupportDirectory();
    final digest = sha256.convert(utf8.encode(raw)).toString().substring(0, 20);
    final file = File(
      '${dir.path}${Platform.pathSeparator}live_tv_import_$digest.m3u',
    );
    await file.writeAsString(raw, flush: true);
    final prefs = await SharedPreferences.getInstance();
    final entries = await _savedKeys(prefs);
    final key = 'file:${file.path}';
    if (!entries.contains(key)) {
      if (entries.length >= _maxSources) {
        await file.delete();
        throw StateError('Se alcanzó el límite de listas M3U.');
      }
      await prefs.setStringList(_sourcesKey, [...entries, key]);
    }
    await prefs.setString(_localPathKey, file.path);
    await prefs.setString(_sourceKindKey, 'file');
  }

  Future<void> removeSource(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final old = await _savedKeys(prefs);
    if (!old.contains(key)) return;
    await prefs.setStringList(
      _sourcesKey,
      old.where((item) => item != key).toList(growable: false),
    );
    // Only allow deletion of known app-owned imported files. Never trust
    // arbitrary paths from playlist sources or SharedPreferences.
    if (key.startsWith('file:')) {
      final dir = await getApplicationSupportDirectory();
      final path = key.substring(5);
      final prefix = '${dir.path}${Platform.pathSeparator}live_tv_import_';
      if (path.startsWith(prefix) &&
          RegExp(r'^[0-9a-f]{20}\\.m3u
    }
  }

  Future<String?> _loadSource(String key) async {
    try {
      if (key.startsWith('file:')) {
        final file = File(key.substring(5));
        if (!await file.exists()) return null;
        if (await file.length() > 10 * 1024 * 1024) return null;
        return file.readAsString();
      }
      if (!key.startsWith('url:')) return null;
      final uri = Uri.tryParse(key.substring(4));
      if (uri == null || !uri.hasAuthority ||
          (uri.scheme != 'https' && uri.scheme != 'http')) return null;
      final response = await _dio.get<String>(
        uri.toString(),
        options: Options(
          responseType: ResponseType.plain,
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 15),
        ),
      );
      final data = response.data;
      if (data == null || data.length > 10 * 1024 * 1024) return null;
      return data;
    } on DioException {
      return null; // One unavailable list must not hide the remaining lists.
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }

  Future<List<LiveChannel>> loadChannels() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = await _savedKeys(prefs);
    if (keys.isEmpty) return const [];
    final raws = await Future.wait([for (final key in keys) _loadSource(key)]);
    final channels = <LiveChannel>[];
    for (final raw in raws) {
      if (raw == null || raw.isEmpty || !raw.trimLeft().startsWith('#EXTM3U')) {
        continue;
      }
      final epg = M3uParser.epgUri(raw);
      if (epg != null && prefs.getString(_epgSourceKey)?.isEmpty != false) {
        await prefs.setString(_epgSourceKey, epg.toString());
      }
      channels.addAll(M3uParser.parse(raw));
    }
    return const LiveTvOrganizer().merge(
      partner: const [],
      local: channels,
      partnerSports: const [],
      publicSports: const [],
    );
  }

}

class LiveChannelsController extends AsyncNotifier<List<LiveChannel>> {
  @override
  Future<List<LiveChannel>> build() async {
    final sources = await Future.wait([
      ref.read(builtInLiveSourceRegistryProvider).mexico(),
      ref.read(liveTvRepositoryProvider).loadChannels(),
    ]);
    return _mergeChannels(sources[0], sources[1]);
  }

  Future<void> setSource(String url) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(liveTvRepositoryProvider).saveSource(url);
      final builtIn = await ref.read(builtInLiveSourceRegistryProvider).mexico();
      final custom = await ref.read(liveTvRepositoryProvider).loadChannels();
      return _mergeChannels(builtIn, custom);
    });
    ref.invalidate(epgProgramsProvider);
  }

  Future<void> setLocalPlaylist(String raw) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(liveTvRepositoryProvider).saveLocalPlaylist(raw);
      final builtIn = await ref.read(builtInLiveSourceRegistryProvider).mexico();
      final custom = await ref.read(liveTvRepositoryProvider).loadChannels();
      return _mergeChannels(builtIn, custom);
    });
    ref.invalidate(epgProgramsProvider);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final builtIn = await ref.read(builtInLiveSourceRegistryProvider).mexico();
      final custom = await ref.read(liveTvRepositoryProvider).loadChannels();
      return _mergeChannels(builtIn, custom);
    });
  }

  Future<void> removeSource(String key) async {
    await ref.read(liveTvRepositoryProvider).removeSource(key);
    await refresh();
  }

  List<LiveChannel> _mergeChannels(
    List<LiveChannel> builtIn,
    List<LiveChannel> custom,
  ) => const LiveTvOrganizer().merge(
        partner: const [],
        local: custom,
        partnerSports: const [],
        publicSports: builtIn,
      );

}

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
    if (url == null || url.trim().isEmpty) return const [];
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
    if (url == null || url.trim().isEmpty) {
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
)
              .hasMatch(path.substring(prefix.length))) {
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
    }
  }

  Future<String?> _loadSource(String key) async {
    try {
      if (key.startsWith('file:')) {
        final file = File(key.substring(5));
        if (!await file.exists()) return null;
        if (await file.length() > 10 * 1024 * 1024) return null;
        return file.readAsString();
      }
      if (!key.startsWith('url:')) return null;
      final uri = Uri.tryParse(key.substring(4));
      if (uri == null || !uri.hasAuthority ||
          (uri.scheme != 'https' && uri.scheme != 'http')) return null;
      final response = await _dio.get<String>(
        uri.toString(),
        options: Options(
          responseType: ResponseType.plain,
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 15),
        ),
      );
      final data = response.data;
      if (data == null || data.length > 10 * 1024 * 1024) return null;
      return data;
    } on DioException {
      return null; // One unavailable list must not hide the remaining lists.
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }

  Future<List<LiveChannel>> loadChannels() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = await _savedKeys(prefs);
    if (keys.isEmpty) return const [];
    final raws = await Future.wait([for (final key in keys) _loadSource(key)]);
    final channels = <LiveChannel>[];
    for (final raw in raws) {
      if (raw == null || raw.isEmpty || !raw.trimLeft().startsWith('#EXTM3U')) {
        continue;
      }
      final epg = M3uParser.epgUri(raw);
      if (epg != null && prefs.getString(_epgSourceKey)?.isEmpty != false) {
        await prefs.setString(_epgSourceKey, epg.toString());
      }
      channels.addAll(M3uParser.parse(raw));
    }
    return const LiveTvOrganizer().merge(
      partner: const [],
      local: channels,
      partnerSports: const [],
      publicSports: const [],
    );
  }

}

class LiveChannelsController extends AsyncNotifier<List<LiveChannel>> {
  @override
  Future<List<LiveChannel>> build() async {
    final sources = await Future.wait([
      ref.read(builtInLiveSourceRegistryProvider).mexico(),
      ref.read(liveTvRepositoryProvider).loadChannels(),
    ]);
    return _mergeChannels(sources[0], sources[1]);
  }

  Future<void> setSource(String url) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(liveTvRepositoryProvider).saveSource(url);
      final builtIn = await ref.read(builtInLiveSourceRegistryProvider).mexico();
      final custom = await ref.read(liveTvRepositoryProvider).loadChannels();
      return _mergeChannels(builtIn, custom);
    });
    ref.invalidate(epgProgramsProvider);
  }

  Future<void> setLocalPlaylist(String raw) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(liveTvRepositoryProvider).saveLocalPlaylist(raw);
      final builtIn = await ref.read(builtInLiveSourceRegistryProvider).mexico();
      final custom = await ref.read(liveTvRepositoryProvider).loadChannels();
      return _mergeChannels(builtIn, custom);
    });
    ref.invalidate(epgProgramsProvider);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final builtIn = await ref.read(builtInLiveSourceRegistryProvider).mexico();
      final custom = await ref.read(liveTvRepositoryProvider).loadChannels();
      return _mergeChannels(builtIn, custom);
    });
  }

  Future<void> removeSource(String key) async {
    await ref.read(liveTvRepositoryProvider).removeSource(key);
    await refresh();
  }

  List<LiveChannel> _mergeChannels(
    List<LiveChannel> builtIn,
    List<LiveChannel> custom,
  ) => const LiveTvOrganizer().merge(
        partner: const [],
        local: custom,
        partnerSports: const [],
        publicSports: builtIn,
      );

}

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
    if (url == null || url.trim().isEmpty) return const [];
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
    if (url == null || url.trim().isEmpty) {
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
