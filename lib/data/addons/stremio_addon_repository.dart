import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/stremio_addon_config.dart';

final stremioAddonRepositoryProvider = Provider<StremioAddonRepository>((ref) {
  return StremioAddonRepository();
});

final stremioAddonsProvider =
    FutureProvider.autoDispose<List<StremioAddonConfig>>((ref) {
  return ref.read(stremioAddonRepositoryProvider).load();
});

/// URLs may contain bearer tokens encoded in path segments (PenguPlay).
/// Keep those URLs in Android Keystore-backed encrypted storage; normal
/// preferences must only contain nonsensitive labels and UUIDs.
abstract class AddonSecretStore {
  Future<void> write(String key, String value);
  Future<String?> read(String key);
  Future<void> delete(String key);
}

class EncryptedAddonSecretStore implements AddonSecretStore {
  final FlutterSecureStorage storage;

  EncryptedAddonSecretStore({FlutterSecureStorage? storage})
      : storage = storage ?? const FlutterSecureStorage();

  @override
  Future<void> write(String key, String value) =>
      storage.write(key: key, value: value);

  @override
  Future<String?> read(String key) => storage.read(key: key);

  @override
  Future<void> delete(String key) => storage.delete(key: key);
}

class StremioAddonRepository {
  static const _key = 'potv_stremio_addons';
  static const _uuid = Uuid();
  static const _secretPrefix = 'potv_stremio_manifest_v2_';

  final AddonSecretStore secrets;

  StremioAddonRepository({AddonSecretStore? secrets})
      : secrets = secrets ?? EncryptedAddonSecretStore();

  String _secretKey(String id) => '$_secretPrefix$id';

  /// Transparently migrates legacy plain-text addon URLs to encrypted storage.
  /// The legacy preference is overwritten *only after* encrypted writes
  /// succeed; if Keystore fails, no credentials are silently discarded.
  Future<List<StremioAddonConfig>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const [];

    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return const [];
    }
    if (decoded is! List) return const [];
    final addons = <StremioAddonConfig>[];
    var needsMigration = false;
    for (final value in decoded) {
      if (value is! Map) continue;
      final row = Map<String, dynamic>.from(value);
      final id = row['id']?.toString() ?? '';
      final name = row['name']?.toString() ?? '';
      if (id.isEmpty || name.isEmpty) continue;

      Uri? uri;
      final legacy = row['manifest_uri']?.toString();
      if (legacy != null && legacy.isNotEmpty) {
        uri = Uri.tryParse(legacy);
        if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) continue;
        await secrets.write(_secretKey(id), uri.toString());
        needsMigration = true;
      } else {
        final secured = await secrets.read(_secretKey(id));
        if (secured == null) continue;
        uri = Uri.tryParse(secured);
        if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) continue;
      }
      addons.add(StremioAddonConfig(
        id: id,
        name: name,
        manifestUri: uri,
        enabled: row['enabled'] != false,
      ));
    }

    if (needsMigration) {
      // Scrub credentials, even for rows that could not be restored.
      await _save(addons);
    }
    return List.unmodifiable(addons);
  }

  Future<StremioAddonConfig> add({
    required String name,
    required Uri manifestUri,
  }) async {
    _validate(manifestUri);
    final existing = [...await load()];
    final duplicate = existing.where((s) => s.manifestUri == manifestUri);
    if (duplicate.isNotEmpty) return duplicate.first;
    final source = StremioAddonConfig(
      id: _uuid.v4(),
      name: name.trim(),
      manifestUri: manifestUri,
    );
    await secrets.write(_secretKey(source.id), manifestUri.toString());
    try {
      await _save([...existing, source]);
    } catch (_) {
      await secrets.delete(_secretKey(source.id));
      rethrow;
    }
    return source;
  }

  Future<void> update(StremioAddonConfig source) async {
    _validate(source.manifestUri);
    final current = [...await load()];
    final i = current.indexWhere((item) => item.id == source.id);
    if (i < 0) return;
    final before = current[i];
    if (before.manifestUri != source.manifestUri) {
      await secrets.write(_secretKey(source.id), source.manifestUri.toString());
    }
    current[i] = source;
    await _save(current);
  }

  Future<void> remove(String id) async {
    final current = [...await load()];
    current.removeWhere((item) => item.id == id);
    await _save(current);
    await secrets.delete(_secretKey(id));
  }

  Future<void> _save(List<StremioAddonConfig> items) async {
    final prefs = await SharedPreferences.getInstance();
    // Do not call StremioAddonConfig.toJson(): it includes manifestUri for
    // legacy serialization and can contain a personal bearer token.
    final safe = [
      for (final s in items)
        {'id': s.id, 'name': s.name, 'enabled': s.enabled},
    ];
    await prefs.setString(_key, jsonEncode(safe));
  }

  void _validate(Uri uri) {
    if (uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
      throw const FormatException('El addon privado debe utilizar HTTPS.');
    }
  }
}
