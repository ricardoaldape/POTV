import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/http_source_config.dart';

final httpSourceRepositoryProvider = Provider<HttpSourceRepository>((ref) {
  return const HttpSourceRepository();
});

final httpSourcesProvider =
    FutureProvider.autoDispose<List<HttpSourceConfig>>((ref) {
  return ref.read(httpSourceRepositoryProvider).load();
});

class HttpSourceRepository {
  static const _key = 'potv_http_sources';
  static const _uuid = Uuid();

  const HttpSourceRepository();

  Future<List<HttpSourceConfig>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.trim().isEmpty) return const [];

    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];

    final result = <HttpSourceConfig>[];
    for (final item in decoded) {
      if (item is! Map<String, dynamic>) continue;
      try {
        result.add(HttpSourceConfig.fromJson(item));
      } on FormatException {
        continue;
      }
    }
    return result;
  }

  Future<HttpSourceConfig> add({
    required String name,
    required Uri endpoint,
  }) async {
    final current = [...await load()];
    final source = HttpSourceConfig(
      id: _uuid.v4(),
      name: name.trim(),
      endpoint: endpoint,
    );
    current.add(source);
    await _save(current);
    return source;
  }

  Future<void> update(HttpSourceConfig source) async {
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

  Future<void> _save(List<HttpSourceConfig> sources) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode([for (final source in sources) source.toJson()]),
    );
  }
}
