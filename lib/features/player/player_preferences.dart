import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class PlayerPreferences {
  static const _profilesKey = 'potv_user_profiles_v2';
  static const _activeProfileKey = 'potv_active_profile_id';

  final String audioLanguage;
  final String subtitleLanguage;
  final bool autoplayNext;

  const PlayerPreferences({
    this.audioLanguage = 'es-419',
    this.subtitleLanguage = 'es',
    this.autoplayNext = true,
  });

  String get media3AudioPreference {
    final value = audioLanguage.toLowerCase();
    if (value == 'en' || value.startsWith('en-')) return 'english';
    if (value == 'original') return 'any';
    return 'spanish';
  }

  String get media3SubtitlePreference =>
      subtitleLanguage.toLowerCase() == 'off'
          ? 'disabled'
          : 'whenNoSpanishAudio';

  static Future<PlayerPreferences> load() async {
    final prefs = await SharedPreferences.getInstance();
    final activeId = prefs.getString(_activeProfileKey);
    final raw = prefs.getString(_profilesKey);
    if (activeId == null || raw == null) {
      return const PlayerPreferences();
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const PlayerPreferences();
      for (final value in decoded) {
        if (value is! Map || value['id']?.toString() != activeId) continue;
        final nested = value['preferences'];
        if (nested is! Map) return const PlayerPreferences();
        return PlayerPreferences(
          audioLanguage: nested['audioLanguage']?.toString() ?? 'es-419',
          subtitleLanguage: nested['subtitleLanguage']?.toString() ?? 'es',
          autoplayNext: nested['autoplayNext'] as bool? ?? true,
        );
      }
    } catch (_) {}
    return const PlayerPreferences();
  }
}
