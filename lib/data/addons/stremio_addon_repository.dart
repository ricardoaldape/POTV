import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/stremio_addon_config.dart';

final stremioAddonRepositoryProvider =
    Provider<StremioAddonRepository>((ref) {
  return const StremioAddonRepository();
});

final stremioAddonsProvider =
    FutureProvider.autoDispose<List<StremioAddonConfig>>((ref) {
  return ref.read(stremioAddonRepositoryProvider).load();
});

class StremioAddonRepository {
  static const _key = 'potv_stremio_addons';
  static const _uuid = Uuid();

  const StremioAddonRepository();

  Future<List<StremioAddonConfig>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.trim().isEmpty) return const [];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];

      final result = <StremioAddonConfig>[];
      for (final value in decoded) {
        if (value is! Map<String, dynamic>) continue;
        try {
          result.add(StremioAddonConfig.fromJson(value));
        } on FormatException {
          continue;
        }
      }
      return result;
    } catch (_) {
      return const [];
    }
  }

  Future<StremioAddonConfig> add({
    required String name,
    required Uri manifestUri,
  }) async {
    final current = [...await load()];
    final source = StremioAddonConfig(
      id: _uuid.v4(),
      name: name.trim(),
      manifestUri: manifestUri,
    );
    current.add(source);
    await _save(current);
    return source;
  }

  Future<void> update(StremioAddonConfig source) async {
    final current = [...await load()];
    final index = current.indexWhere((item) => item.id == source.id);
    if (index < 0) return;
    current[index] = source;
    await _save(current);
  }

  Future<void> remove(String id) async {
    final current = [...await load()]
      ..removeWhere((item) => item.id == id);
    await _save(current);
  }

  Future<void> _save(List<StremioAddonConfig> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode([for (final item in items) item.toJson()]),
    );
  }
}
