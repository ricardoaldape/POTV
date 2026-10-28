import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class PlayerPreferences {
  static const _profilesKey = 'potv_user_profiles_v2';
  static const _activeProfileKey = 'potv_active_profile_id';

  final String audioLanguage;
  final String subtitleLanguage;
  final bool autoplayNext;
  /// 0 = adaptive/automatic, otherwise cap native video height in pixels.
  final int preferredVideoHeight;
  /// 0 = best/automatic; >0 = chosen audio track bitrate ceiling.
  final int preferredAudioBitrate;

  const PlayerPreferences({
    this.audioLanguage = 'es-419',
    this.subtitleLanguage = 'es',
    this.autoplayNext = true,
    this.preferredVideoHeight = 0,
    this.preferredAudioBitrate = 0,
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

  /// Only update the active profile; keep every unrelated user setting.
  /// The same preference is applied again when failover opens another server.
  static Future<PlayerPreferences> updateCurrent({
    String? audioLanguage,
    String? subtitleLanguage,
    int? preferredVideoHeight,
    int? preferredAudioBitrate,
  }) async {
    final current = await load();
    final updated = PlayerPreferences(
      audioLanguage: audioLanguage ?? current.audioLanguage,
      subtitleLanguage: subtitleLanguage ?? current.subtitleLanguage,
      autoplayNext: current.autoplayNext,
      preferredVideoHeight:
          preferredVideoHeight ?? current.preferredVideoHeight,
      preferredAudioBitrate:
          preferredAudioBitrate ?? current.preferredAudioBitrate,
    );
    final prefs = await SharedPreferences.getInstance();
    final activeId = prefs.getString(_activeProfileKey);
    final raw = prefs.getString(_profilesKey);
    if (activeId == null || raw == null) return updated;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return updated;
      var changed = false;
      final profiles = decoded.map((profile) {
        if (profile is! Map || profile['id']?.toString() != activeId) {
          return profile;
        }
        changed = true;
        final nested = profile['preferences'];
        return {
          ...profile,
          'preferences': {
            if (nested is Map) ...nested,
            'audioLanguage': updated.audioLanguage,
            'subtitleLanguage': updated.subtitleLanguage,
            'preferredVideoHeight': updated.preferredVideoHeight,
            'preferredAudioBitrate': updated.preferredAudioBitrate,
          },
        };
      }).toList();
      if (changed) {
        await prefs.setString(_profilesKey, jsonEncode(profiles));
      }
    } catch (_) {
      // A corrupt profile must not break the player.
    }
    return updated;
  }

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
          preferredVideoHeight:
              (nested['preferredVideoHeight'] as num?)?.toInt() ?? 0,
          preferredAudioBitrate:
              (nested['preferredAudioBitrate'] as num?)?.toInt() ?? 0,
        );
      }
    } catch (_) {}
    return const PlayerPreferences();
  }
}
