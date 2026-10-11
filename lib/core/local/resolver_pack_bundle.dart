import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../data/addons/stremio_addon_repository.dart';
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

  /// No private addon manifest URI is exported via plain JSON or clipboard.
  /// Optional provider connections stay encrypted on their original device.
  static Future<String> exportJson() async {
    final prefs = await SharedPreferences.getInstance();
    return jsonEncode({
      'format': format,
      'version': version,
      'http_sources': _decodeList(prefs.getString(_httpSourcesKey)),
      'stremio_addons': const [],
    });
  }

  static Future<ResolverPackImportResult> importJson(
    String raw, {
    StremioAddonRepository? addonRepository,
  }) async {
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
    final currentHttp =
        _parseHttpSources(_decodeList(prefs.getString(_httpSourcesKey)));
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

    // A manually imported resolver pack may contain private addon URLs:
    // immediately transfer them to encrypted platform storage. Never
    // serialize them into SharedPreferences or debug output.
    final repository = addonRepository ?? StremioAddonRepository();
    final existing = await repository.load();
    final manifests = {
      for (final addon in existing) _normalizedUri(addon.manifestUri),
    };
    var addonsAdded = 0;
    for (final addon in incomingAddons) {
      final key = _normalizedUri(addon.manifestUri);
      if (!manifests.add(key)) continue;
      final created = await repository.add(
        name: addon.name, manifestUri: addon.manifestUri,
      );
      if (!addon.enabled) {
        await repository.update(created.copyWith(enabled: false));
      }
      addonsAdded++;
    }

    await prefs.setString(
      _httpSourcesKey,
      jsonEncode([for (final source in httpByEndpoint.values) source.toJson()]),
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

  static List<HttpSourceConfig> _parseHttpSources(Object? raw) {
    if (raw is! List) return const [];
    final result = <HttpSourceConfig>[];
    for (final item in raw) {
      if (item is! Map) continue;
      try {
        result.add(HttpSourceConfig.fromJson(
          item.map((key, value) => MapEntry(key.toString(), value)),
        ));
      } on FormatException {
        throw const FormatException('Resolver HTTP inválido en el paquete');
      }
    }
    return result;
  }

  static List<StremioAddonConfig> _parseAddons(Object? raw) {
    if (raw is! List) return const [];
    final result = <StremioAddonConfig>[];
    for (final item in raw) {
      if (item is! Map) continue;
      try {
        result.add(StremioAddonConfig.fromJson(
          item.map((key, value) => MapEntry(key.toString(), value)),
        ));
      } on FormatException {
        throw const FormatException('Addon inválido en el paquete');
      }
    }
    return result;
  }

  static String _normalizedUri(Uri uri) {
    var text = uri.replace(fragment: null).toString().trim();
    while (text.endsWith('/')) {
      text = text.substring(0, text.length - 1);
    }
    return text.toLowerCase();
  }
}
