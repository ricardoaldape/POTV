import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Storage namespaces for independent POTV user profiles.
///
/// Legacy global data is migrated once, to the *first* saved profile, to
/// prevent another profile accidentally inheriting someone else's history.
class ProfileScopedStorage {
  static const activeProfileKey = 'potv_active_profile_id';
  static const profilesKey = 'potv_user_profiles';
  static const historyKey = 'potv_playback_history_v1';
  static const liveTvFavoritesKey = 'live_tv_favorite_channels';

  const ProfileScopedStorage._();

  static String scopedKey(String legacyKey, String profileId) =>
      '$legacyKey.profile.${Uri.encodeComponent(profileId)}';

  static Future<String> activeKey(
    SharedPreferences prefs,
    String legacyKey,
  ) async {
    final active = prefs.getString(activeProfileKey);
    if (active == null || active.isEmpty) return legacyKey;

    final first = _firstProfileId(prefs) ?? active;
    final legacyValue = prefs.get(legacyKey);
    if (legacyValue != null) {
      final firstKey = scopedKey(legacyKey, first);
      if (!prefs.containsKey(firstKey)) {
        bool saved = false;
        if (legacyValue is String) {
          saved = await prefs.setString(firstKey, legacyValue);
        } else if (legacyValue is List<String>) {
          saved = await prefs.setStringList(firstKey, legacyValue);
        }
        if (saved) await prefs.remove(legacyKey);
      } else {
        await prefs.remove(legacyKey);
      }
    }
    return scopedKey(legacyKey, active);
  }

  static String? _firstProfileId(SharedPreferences prefs) {
    try {
      final raw = prefs.getString(profilesKey);
      if (raw == null) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! List || decoded.isEmpty) return null;
      final first = decoded.first;
      if (first is! Map<String, dynamic>) return null;
      final id = first['id'];
      return id is String && id.isNotEmpty ? id : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearProfile(
    SharedPreferences prefs,
    String profileId,
  ) async {
    if (profileId.isEmpty) return;
    await prefs.remove(scopedKey(historyKey, profileId));
    await prefs.remove(scopedKey(liveTvFavoritesKey, profileId));
  }
}
