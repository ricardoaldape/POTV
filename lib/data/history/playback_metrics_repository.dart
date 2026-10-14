import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class PlaybackMetricsRepository {
  static const _prefix = 'potv_playback_metrics_v1_';
  static const _activeProfileKey = 'potv_active_profile_id';
  static const _maxEvents = 100;

  const PlaybackMetricsRepository();

  Future<String> _key(SharedPreferences prefs) async {
    final profile = prefs.getString(_activeProfileKey)?.trim();
    return _prefix + ((profile == null || profile.isEmpty) ? 'guest' : profile);
  }

  Future<void> recordStartup(String mediaKey, int milliseconds) =>
      _append('startup_ms', mediaKey, milliseconds);

  Future<void> recordFailure(String mediaKey) =>
      _append('failure', mediaKey, 1);

  Future<void> recordWatchTime(String mediaKey, Duration duration) =>
      _append('watch_ms', mediaKey, duration.inMilliseconds);

  Future<void> _append(String type, String mediaKey, int value) async {
    final prefs = await SharedPreferences.getInstance();
    final key = await _key(prefs);
    var events = <Map<String, dynamic>>[];
    final raw = prefs.getString(key);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          events = decoded
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList();
        }
      } catch (_) {}
    }

    events.add({
      'type': type,
      'mediaKey': mediaKey,
      'value': value,
      'at': DateTime.now().toUtc().toIso8601String(),
    });
    if (events.length > _maxEvents) {
      events = events.sublist(events.length - _maxEvents);
    }
    await prefs.setString(key, jsonEncode(events));
  }
}
