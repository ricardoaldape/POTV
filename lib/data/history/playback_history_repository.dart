import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/playback_history_entry.dart';
import '../../providers/user_providers.dart';
import '../accounts/profile_scoped_storage.dart';

final playbackHistoryProvider = FutureProvider.autoDispose<List<PlaybackHistoryEntry>>(
  (ref) {
    // Reload the rail immediately when the viewer switches profile.
    ref.watch(currentProfileIdProvider);
    return const PlaybackHistoryRepository().all();
  },
);

class PlaybackHistoryRepository {
  static const _key = ProfileScopedStorage.historyKey;

  const PlaybackHistoryRepository();

  Future<List<PlaybackHistoryEntry>> all() async {
    final prefs = await SharedPreferences.getInstance();
    final key = await ProfileScopedStorage.activeKey(prefs, _key);
    return _readEntries(prefs, key);
  }

  List<PlaybackHistoryEntry> _readEntries(
    SharedPreferences prefs,
    String key,
  ) {
    final raw = prefs.getString(key);
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
    final key = await ProfileScopedStorage.activeKey(prefs, _key);
    final entries = [..._readEntries(prefs, key)]
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
