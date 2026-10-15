import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/playback_history_entry.dart';

final playbackHistoryProvider =
    FutureProvider.autoDispose<List<PlaybackHistoryEntry>>(
  (ref) => const PlaybackHistoryRepository().all(),
);

class PlaybackHistoryRepository {
  static const _legacyKey = 'potv_playback_history_v1';
  static const _prefix = 'potv_playback_history_v2_';
  static const _activeProfileKey = 'potv_active_profile_id';

  const PlaybackHistoryRepository();

  Future<String> _storageKey(SharedPreferences prefs) async {
    final profile = prefs.getString(_activeProfileKey)?.trim();
    final suffix = profile != null && profile.isNotEmpty ? profile : 'guest';
    return _prefix + suffix;
  }

  Future<List<PlaybackHistoryEntry>> all() async {
    final prefs = await SharedPreferences.getInstance();
    final key = await _storageKey(prefs);
    var raw = prefs.getString(key);

    if (raw == null) {
      final legacy = prefs.getString(_legacyKey);
      if (legacy != null && legacy.trim().isNotEmpty) {
        raw = legacy;
        await prefs.setString(key, legacy);
        await prefs.remove(_legacyKey);
      }
    }
    if (raw == null || raw.trim().isEmpty) return const [];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final entries = <PlaybackHistoryEntry>[];
      for (final value in decoded) {
        if (value is! Map) continue;
        final entry =
            PlaybackHistoryEntry.fromJson(Map<String, dynamic>.from(value));
        if (entry.key.isNotEmpty) entries.add(entry);
      }
      entries.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return entries;
    } catch (_) {
      return const [];
    }
  }

  Future<PlaybackHistoryEntry?> get(String key) async {
    for (final entry in await all()) {
      if (entry.key == key) return entry;
    }
    return null;
  }

  Future<PlaybackHistoryEntry?> latestForMedia({
    required int mediaId,
    required String mediaType,
  }) async {
    for (final entry in await all()) {
      if (entry.mediaId == mediaId && entry.mediaType == mediaType) {
        return entry;
      }
    }
    return null;
  }

  Future<void> save(PlaybackHistoryEntry entry) async {
    final prefs = await SharedPreferences.getInstance();
    final key = await _storageKey(prefs);
    final entries = [...await all()]
      ..removeWhere((item) => item.key == entry.key)
      ..insert(0, entry);
    if (entries.length > 100) {
      entries.removeRange(100, entries.length);
    }
    await prefs.setString(
      key,
      jsonEncode([for (final item in entries) item.toJson()]),
    );
  }
}
