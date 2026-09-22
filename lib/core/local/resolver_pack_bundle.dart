import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/http_source_config.dart';
import '../../domain/models/stremio_addon_config.dart';

class ResolverPackImportResult {
  final int httpSourcesAdded;
  final int addonsAdded;

  const ResolverPackImportResult({
    required this.httpSourcesAdded,
    required this.addonsAdded,
  });

  int get totalAdded => httpSourcesAdded + addonsAdded;
}

class ResolverPackBundle {
  static const format = 'potv-resolver-pack';
  static const version = 1;
  static const _uuid = Uuid();

  static const _httpSourcesKey = 'potv_http_sources';
  static const _stremioAddonsKey = 'potv_stremio_addons';

  static Future<String> exportJson() async {
    final prefs = await SharedPreferences.getInstance();
    return jsonEncode({
      'format': format,
      'version': version,
      'http_sources': _decodeList(prefs.getString(_httpSourcesKey)),
      'stremio_addons': _decodeList(prefs.getString(_stremioAddonsKey)),
    });
  }

  static Future<ResolverPackImportResult> importJson(String raw) async {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic> || decoded['format'] != format) {
      throw const FormatException('Paquete de resolvers POTV inválido');
    }

    final incomingVersion = decoded['version'];
    if (incomingVersion is! int || incomingVersion > version) {
      throw const FormatException('Versión de Resolver Pack no compatible');
    }

    final incomingHttp = _parseHttpSources(decoded['http_sources']);
    final incomingAddons = _parseAddons(decoded['stremio_addons']);

    final prefs = await SharedPreferences.getInstance();
    final currentHttp = _parseHttpSources(_decodeList(prefs.getString(_httpSourcesKey)));
    final currentAddons =
        _parseAddons(_decodeList(prefs.getString(_stremioAddonsKey)));

    final httpByEndpoint = <String, HttpSourceConfig>{
      for (final source in currentHttp) _normalizedUri(source.endpoint): source,
    };
    var httpAdded = 0;
    for (final source in incomingHttp) {
      final key = _normalizedUri(source.endpoint);
      if (httpByEndpoint.containsKey(key)) continue;
      httpByEndpoint[key] = HttpSourceConfig(
        id: source.id.trim().isEmpty ? _uuid.v4() : source.id,
        name: source.name,
        endpoint: source.endpoint,
        enabled: source.enabled,
      );
      httpAdded++;
    }

    final addonByManifest = <String, StremioAddonConfig>{
      for (final addon in currentAddons) _normalizedUri(addon.manifestUri): addon,
    };
    var addonsAdded = 0;
    for (final addon in incomingAddons) {
      final key = _normalizedUri(addon.manifestUri);
      if (addonByManifest.containsKey(key)) continue;
      addonByManifest[key] = StremioAddonConfig(
        id: addon.id.trim().isEmpty ? _uuid.v4() : addon.id,
        name: addon.name,
        manifestUri: addon.manifestUri,
        enabled: addon.enabled,
      );
      addonsAdded++;
    }

    await prefs.setString(
      _httpSourcesKey,
      jsonEncode([for (final item in httpByEndpoint.values) item.toJson()]),
    );
    await prefs.setString(
      _stremioAddonsKey,
      jsonEncode([for (final item in addonByManifest.values) item.toJson()]),
    );

    return ResolverPackImportResult(
      httpSourcesAdded: httpAdded,
      addonsAdded: addonsAdded,
    );
  }

  static List<Object?> _decodeList(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      return decoded is List ? decoded : const [];
    } catch (_) {
      return const [];
    }
  }

  static List<HttpSourceConfig> _parseHttpSources(Object? value) {
    if (value is! List) return const [];
    final result = <HttpSourceConfig>[];
    for (final item in value) {
      if (item is! Map) continue;
      try {
        result.add(
          HttpSourceConfig.fromJson(
            item.map((key, value) => MapEntry(key.toString(), value)),
          ),
        );
      } on FormatException {
        throw const FormatException('Resolver HTTP inválido en el paquete');
      }
    }
    return result;
  }

  static List<StremioAddonConfig> _parseAddons(Object? value) {
    if (value is! List) return const [];
    final result = <StremioAddonConfig>[];
    for (final item in value) {
      if (item is! Map) continue;
      try {
        result.add(
          StremioAddonConfig.fromJson(
            item.map((key, value) => MapEntry(key.toString(), value)),
          ),
        );
      } on FormatException {
        throw const FormatException('Addon inválido en el paquete');
      }
    }
    return result;
  }

  static String _normalizedUri(Uri uri) {
    var value = uri.replace(fragment: null).toString().trim();
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value.toLowerCase();
  }
}
