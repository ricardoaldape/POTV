import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/playback_history_entry.dart';

class PlaybackHistoryRepository {
  static const _key = 'potv_playback_history_v1';

  const PlaybackHistoryRepository();

  Future<List<PlaybackHistoryEntry>> all() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.trim().isEmpty) return const [];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final entries = <PlaybackHistoryEntry>[];
      for (final value in decoded) {
        if (value is! Map<String, dynamic>) continue;
        final entry = PlaybackHistoryEntry.fromJson(value);
        if (entry.key.isNotEmpty) entries.add(entry);
      }
      entries.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return entries;
    } catch (_) {
      return const [];
    }
  }

  Future<PlaybackHistoryEntry?> get(String key) async {
    final entries = await all();
    for (final entry in entries) {
      if (entry.key == key) return entry;
    }
    return null;
  }

  Future<PlaybackHistoryEntry?> latestForMedia({
    required int mediaId,
    required String mediaType,
  }) async {
    final entries = await all();
    for (final entry in entries) {
      if (entry.mediaId == mediaId && entry.mediaType == mediaType) {
        return entry;
      }
    }
    return null;
  }

  Future<void> save(PlaybackHistoryEntry entry) async {
    final prefs = await SharedPreferences.getInstance();
    final entries = [...await all()]
      ..removeWhere((item) => item.key == entry.key)
      ..insert(0, entry);

    if (entries.length > 100) {
      entries.removeRange(100, entries.length);
    }

    await prefs.setString(
      _key,
      jsonEncode([for (final item in entries) item.toJson()]),
    );
  }
}
