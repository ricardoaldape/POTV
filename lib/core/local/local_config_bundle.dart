import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class LocalConfigBundle {
  static const format = 'potv-local-config';
  static const version = 1;

  static const _m3uKey = 'live_tv_m3u_url';
  static const _epgKey = 'live_tv_xmltv_url';
  static const _httpSourcesKey = 'potv_http_sources';
  static const _stremioAddonsKey = 'potv_stremio_addons';

  static Future<String> exportJson() async {
    final prefs = await SharedPreferences.getInstance();

    final data = <String, Object?>{
      'format': format,
      'version': version,
      'live_tv': {
        'm3u_url': prefs.getString(_m3uKey),
        'xmltv_url': prefs.getString(_epgKey),
      },
      'http_sources': _decodeSources(prefs.getString(_httpSourcesKey)),
      'stremio_addons': _decodeSources(prefs.getString(_stremioAddonsKey)),
    };

    return jsonEncode(data);
  }

  static Future<void> importJson(String raw) async {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Configuración POTV inválida');
    }
    if (decoded['format'] != format) {
      throw const FormatException('El archivo no es una configuración POTV');
    }

    final incomingVersion = decoded['version'];
    if (incomingVersion is! int || incomingVersion > version) {
      throw const FormatException('Versión de configuración no compatible');
    }

    final prefs = await SharedPreferences.getInstance();

    final liveTv = decoded['live_tv'];
    if (liveTv is Map<String, dynamic>) {
      await _writeOptionalString(prefs, _m3uKey, liveTv['m3u_url']);
      await _writeOptionalString(prefs, _epgKey, liveTv['xmltv_url']);
    }

    final httpSources = decoded['http_sources'];
    if (httpSources is List) {
      await prefs.setString(_httpSourcesKey, jsonEncode(httpSources));
    }

    final stremioAddons = decoded['stremio_addons'];
    if (stremioAddons is List) {
      await prefs.setString(_stremioAddonsKey, jsonEncode(stremioAddons));
    }
  }

  static List<Object?> _decodeSources(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      return decoded is List ? decoded : const [];
    } catch (_) {
      return const [];
    }
  }

  static Future<void> _writeOptionalString(
    SharedPreferences prefs,
    String key,
    Object? value,
  ) async {
    if (value is String && value.trim().isNotEmpty) {
      await prefs.setString(key, value.trim());
    } else {
      await prefs.remove(key);
    }
  }
}
