import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/nuvio_plugin_config.dart';

final nuvioPluginRepositoryProvider = Provider<NuvioPluginRepository>((ref) {
  return NuvioPluginRepository(Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 15),
    headers: const {'Accept': 'application/json,text/plain,*/*'},
  )));
});

final nuvioPluginsProvider = FutureProvider.autoDispose<List<NuvioPluginConfig>>((ref) {
  return ref.read(nuvioPluginRepositoryProvider).load();
});

class NuvioRepositoryInstallResult {
  final String name;
  final int added;
  final int total;
  const NuvioRepositoryInstallResult({required this.name, required this.added, required this.total});
}

class NuvioPluginRepository {
  static const _key = 'potv_nuvio_plugins';
  final Dio _dio;
  NuvioPluginRepository(this._dio);

  Future<List<NuvioPluginConfig>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final value in decoded)
          if (value is Map<String, dynamic>)
            tryParse(value),
      ].whereType<NuvioPluginConfig>().toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  static NuvioPluginConfig? tryParse(Map<String, dynamic> json) {
    try { return NuvioPluginConfig.fromJson(json); } catch (_) { return null; }
  }

  Future<NuvioRepositoryInstallResult> addRepository(Uri manifestUri) async {
    final response = await _dio.getUri<Object?>(manifestUri, options: Options(responseType: ResponseType.json));
    final raw = response.data;
    if (raw is! Map<String, dynamic>) throw const FormatException('El repositorio no devolvió un manifest JSON válido.');
    final parsed = parseManifest(manifestUri, raw);
    final current = [...await load()];
    final existing = {for (final item in current) item.id: item};
    var added = 0;
    for (final plugin in parsed.plugins) {
      if (!existing.containsKey(plugin.id)) added++;
      existing[plugin.id] = plugin;
    }
    final merged = existing.values.toList()..sort((a, b) => a.name.compareTo(b.name));
    await _save(merged);
    return NuvioRepositoryInstallResult(name: parsed.name, added: added, total: parsed.plugins.length);
  }

  Future<void> update(NuvioPluginConfig plugin) async {
    final current = [...await load()];
    final index = current.indexWhere((item) => item.id == plugin.id);
    if (index < 0) return;
    current[index] = plugin;
    await _save(current);
  }

  Future<void> remove(String id) async {
    final current = [...await load()]..removeWhere((item) => item.id == id);
    await _save(current);
  }

  Future<void> _save(List<NuvioPluginConfig> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode([for (final item in items) item.toJson()]));
  }

  static ({String name, List<NuvioPluginConfig> plugins}) parseManifest(Uri manifestUri, Map<String, dynamic> raw) {
    final repoName = raw['name']?.toString().trim();
    final scrapers = raw['scrapers'];
    if (repoName == null || repoName.isEmpty || scrapers is! List) {
      throw const FormatException('No parece un repositorio de plugins compatible con Nuvio.');
    }
    final plugins = <NuvioPluginConfig>[];
    for (final value in scrapers) {
      if (value is! Map<String, dynamic>) continue;
      final scraperId = value['id']?.toString().trim();
      final name = value['name']?.toString().trim();
      final version = value['version']?.toString().trim() ?? '0';
      final filename = value['filename']?.toString().trim();
      if (scraperId == null || scraperId.isEmpty || name == null || name.isEmpty || filename == null || filename.isEmpty) continue;
      final typesRaw = value['supportedTypes'];
      final types = typesRaw is List
          ? typesRaw.map((v) => NuvioPluginConfig.normalizeType(v.toString())).where((v) => v.isNotEmpty).toSet()
          : <String>{'movie', 'tv'};
      if (types.contains('anime')) types.add('tv');
      final scriptUri = manifestUri.resolve(filename);
      plugins.add(NuvioPluginConfig(
        id: '${manifestUri.toString()}#$scraperId',
        repositoryName: repoName,
        repositoryUri: manifestUri,
        name: name,
        version: version,
        scriptUri: scriptUri,
        supportedMediaTypes: types,
        enabled: value['enabled'] != false,
      ));
    }
    if (plugins.isEmpty) throw const FormatException('El repositorio no contiene plugins utilizables.');
    return (name: repoName, plugins: plugins);
  }
}
