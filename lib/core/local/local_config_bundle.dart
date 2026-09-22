import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class LocalConfigBundle {
  static const format = 'potv-local-config';
  static const version = 1;

  static const _m3uKey = 'live_tv_m3u_url';
  static const _epgKey = 'live_tv_xmltv_url';

  static Future<String> exportJson() async {
    final prefs = await SharedPreferences.getInstance();

    final data = <String, Object?>{
      'format': format,
      'version': version,
      'live_tv': {
        'm3u_url': prefs.getString(_m3uKey),
        'xmltv_url': prefs.getString(_epgKey),
      },
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

    final liveTv = decoded['live_tv'];
    if (liveTv is! Map<String, dynamic>) return;

    final prefs = await SharedPreferences.getInstance();
    await _writeOptionalString(prefs, _m3uKey, liveTv['m3u_url']);
    await _writeOptionalString(prefs, _epgKey, liveTv['xmltv_url']);
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
