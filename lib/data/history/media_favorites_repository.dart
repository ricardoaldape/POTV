import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/media_item.dart';

final mediaFavoritesProvider = FutureProvider.autoDispose<List<MediaItem>>(
  (ref) => const MediaFavoritesRepository().all(),
);

class MediaFavoritesRepository {
  static const _prefix = 'potv_media_favorites_v1_';
  static const _activeProfileKey = 'potv_active_profile_id';

  const MediaFavoritesRepository();

  Future<String> _key() async {
    final prefs = await SharedPreferences.getInstance();
    final profile = prefs.getString(_activeProfileKey)?.trim();
    final suffix = profile != null && profile.isNotEmpty ? profile : 'guest';
    return _prefix + suffix;
  }

  Map<String, dynamic> _toJson(MediaItem item) => {
        'id': item.id,
        'type': item.mediaTypeName,
        'title': item.title,
        'overview': item.overview,
        'year': item.year,
        'poster': item.poster?.toString(),
        'backdrop': item.backdrop?.toString(),
        'externalId': item.externalId,
        'episodeCount': item.episodeCount,
      };

  MediaItem? _fromJson(Map<String, dynamic> json) {
    final type = switch (json['type']?.toString()) {
      'movie' => MediaType.movie,
      'tv' => MediaType.tv,
      'anime' => MediaType.anime,
      _ => null,
    };
    final id = int.tryParse(json['id']?.toString() ?? '');
    if (type == null || id == null) return null;
    return MediaItem(
      id: id,
      type: type,
      title: json['title']?.toString() ?? 'POTV',
      overview: json['overview']?.toString(),
      year: json['year']?.toString(),
      poster: Uri.tryParse(json['poster']?.toString() ?? ''),
      backdrop: Uri.tryParse(json['backdrop']?.toString() ?? ''),
      externalId: json['externalId']?.toString(),
      episodeCount: int.tryParse(json['episodeCount']?.toString() ?? ''),
    );
  }

  Future<List<MediaItem>> all() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(await _key());
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((value) => _fromJson(Map<String, dynamic>.from(value)))
          .whereType<MediaItem>()
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<bool> contains(MediaItem item) async =>
      (await all()).any((value) => value.id == item.id && value.type == item.type);

  Future<bool> toggle(MediaItem item) async {
    final prefs = await SharedPreferences.getInstance();
    final items = [...await all()];
    final index =
        items.indexWhere((value) => value.id == item.id && value.type == item.type);
    final added = index < 0;
    if (added) {
      items.insert(0, item);
    } else {
      items.removeAt(index);
    }
    await prefs.setString(
      await _key(),
      jsonEncode([for (final value in items) _toJson(value)]),
    );
    return added;
  }
}
