import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/youtube_models.dart';

final youtubeLibraryRepositoryProvider = Provider<YoutubeLibraryRepository>((ref) {
  return const YoutubeLibraryRepository();
});

final youtubeBookmarksProvider = FutureProvider<List<PotvYoutubeVideo>>((ref) {
  return ref.read(youtubeLibraryRepositoryProvider).bookmarks();
});

final youtubeHistoryProvider = FutureProvider<List<PotvYoutubeVideo>>((ref) {
  return ref.read(youtubeLibraryRepositoryProvider).history();
});

class YoutubeLibraryRepository {
  static const _bookmarksKey = 'potv_youtube_bookmarks_v1';
  static const _historyKey = 'potv_youtube_history_v1';
  static const _historyLimit = 100;

  const YoutubeLibraryRepository();

  Future<List<PotvYoutubeVideo>> bookmarks() => _load(_bookmarksKey);
  Future<List<PotvYoutubeVideo>> history() => _load(_historyKey);

  Future<bool> isBookmarked(String videoId) async {
    return (await bookmarks()).any((item) => item.id == videoId);
  }

  Future<void> toggleBookmark(PotvYoutubeVideo video) async {
    final items = [...await bookmarks()];
    final index = items.indexWhere((item) => item.id == video.id);
    if (index >= 0) {
      items.removeAt(index);
    } else {
      items.insert(0, video);
    }
    await _save(_bookmarksKey, items);
  }

  Future<void> addToHistory(PotvYoutubeVideo video) async {
    final items = [...await history()]..removeWhere((item) => item.id == video.id);
    items.insert(0, video);
    if (items.length > _historyLimit) {
      items.removeRange(_historyLimit, items.length);
    }
    await _save(_historyKey, items);
  }

  Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey);
  }

  Future<List<PotvYoutubeVideo>> _load(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((item) => PotvYoutubeVideo.fromJson(Map<String, dynamic>.from(item)))
          .where((item) => item.id.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> _save(String key, List<PotvYoutubeVideo> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      key,
      jsonEncode([for (final item in items) item.toJson()]),
    );
  }
}
