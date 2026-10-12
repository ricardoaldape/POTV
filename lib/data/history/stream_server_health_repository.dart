import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/stream_candidate.dart';

/// Keeps a *per-title* preference for the last functioning server for 3h,
/// without storing source URLs, signatures, request headers or bearer tokens.
/// Success also clears a server's consecutive failure counter.
class StreamServerHealthRepository {
  static const _prefsKey = 'potv_playback_server_health_v1';
  static const _preferenceLifetime = Duration(hours: 3);
  static const _maxTitles = 120;
  const StreamServerHealthRepository();

  String _hash(String input) => sha256.convert(utf8.encode(input)).toString();
  String _mediaKey(String titleKey) => _hash(titleKey);
  String _sourceKey(StreamCandidate source) => _hash(
        '${source.id}|${source.backend.name}|${source.uri.host}',
      );

  Future<Map<String, dynamic>> _read(SharedPreferences prefs) async {
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return {};
    try {
      final value = jsonDecode(raw);
      if (value is Map<String, dynamic>) return value;
    } on FormatException {
      // Recover from corrupt local preferences.
    }
    return {};
  }

  Map<String, dynamic> _entry(Map<String, dynamic> data, String titleKey) {
    final key = _mediaKey(titleKey);
    final value = data[key];
    if (value is Map<String, dynamic>) return value;
    final created = <String, dynamic>{};
    data[key] = created;
    return created;
  }

  Future<List<StreamCandidate>> rankFor(
    String titleKey,
    List<StreamCandidate> candidates,
  ) async {
    if (candidates.length < 2) return candidates;
    final prefs = await SharedPreferences.getInstance();
    final data = await _read(prefs);
    final item = _entry(data, titleKey);
    final preferred = item['preferred'];
    final lastAt = (item['lastAt'] as num?)?.toInt() ?? 0;
    final fresh = DateTime.now().millisecondsSinceEpoch - lastAt <
            _preferenceLifetime.inMilliseconds &&
        lastAt > 0;
    final failureAt = (item['lastErrorAt'] as num?)?.toInt() ?? 0;
    final errorsFresh = failureAt > 0 &&
        DateTime.now().millisecondsSinceEpoch - failureAt <
            _preferenceLifetime.inMilliseconds;
    final failures = item['failures'];
    final stored = errorsFresh && failures is Map ? failures : const {};
    int score(StreamCandidate source) {
      final id = _sourceKey(source);
      final preference = fresh && preferred == id ? 200 : 0;
      final failure = stored[id];
      final count = failure is num ? failure.toInt() : 0;
      // Prefer POTV's native player over an embedded third-party page, even
      // when a WebView happened to play successfully in the last session.
      // Repeated native failures still let a functional fallback move first.
      final nativePriority =
          source.backend == PlaybackBackend.native ? 240 : 0;
      return nativePriority + preference - (count.clamp(0, 6) * 70);
    }

    final sorted = [...candidates];
    // Stable: tied sources keep the original language/quality ranking.
    final order = <String, int>{};
    for (var i = 0; i < candidates.length; i++) {
      order[_sourceKey(candidates[i])] = i;
    }
    sorted.sort((a, b) {
      final byHealth = score(b).compareTo(score(a));
      return byHealth != 0
          ? byHealth
          : (order[_sourceKey(a)] ?? 0).compareTo(order[_sourceKey(b)] ?? 0);
    });
    return sorted;
  }

  Future<void> reportPlaying(String titleKey, StreamCandidate source) async {
    final prefs = await SharedPreferences.getInstance();
    final data = await _read(prefs);
    final entry = _entry(data, titleKey);
    final key = _sourceKey(source);
    entry['preferred'] = key;
    entry['lastAt'] = DateTime.now().millisecondsSinceEpoch;
    final failures = entry['failures'];
    if (failures is Map) failures.remove(key);
    await _save(prefs, data);
  }

  Future<void> reportError(String titleKey, StreamCandidate source) async {
    final prefs = await SharedPreferences.getInstance();
    final data = await _read(prefs);
    final entry = _entry(data, titleKey);
    final key = _sourceKey(source);
    final now = DateTime.now().millisecondsSinceEpoch;
    final previousErrorAt = (entry['lastErrorAt'] as num?)?.toInt() ?? 0;
    if (previousErrorAt == 0 ||
        now - previousErrorAt > _preferenceLifetime.inMilliseconds) {
      entry['failures'] = <String, dynamic>{};
    }
    entry['lastErrorAt'] = now;
    final failures = entry['failures'] is Map<String, dynamic>
        ? entry['failures'] as Map<String, dynamic>
        : <String, dynamic>{};
    final count = failures[key] is num ? (failures[key] as num).toInt() : 0;
    failures[key] = (count + 1).clamp(0, 6);
    entry['failures'] = failures;
    if (failures[key] >= 3 && entry['preferred'] == key) {
      entry.remove('preferred');
    }
    await _save(prefs, data);
  }

  Future<void> _save(SharedPreferences prefs, Map<String, dynamic> data) async {
    if (data.length > _maxTitles) {
      final oldest = data.entries.toList()
        ..sort((a, b) {
          final left = a.value is Map ? (a.value as Map)['lastAt'] : null;
          final right = b.value is Map ? (b.value as Map)['lastAt'] : null;
          return ((left as num?)?.toInt() ?? 0)
              .compareTo((right as num?)?.toInt() ?? 0);
        });
      for (final item in oldest.take(data.length - _maxTitles)) {
        data.remove(item.key);
      }
    }
    await prefs.setString(_prefsKey, jsonEncode(data));
  }
}
