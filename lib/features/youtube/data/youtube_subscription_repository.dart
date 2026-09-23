import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/youtube_models.dart';

final youtubeSubscriptionRepositoryProvider =
    Provider<YoutubeSubscriptionRepository>((ref) {
  return const YoutubeSubscriptionRepository();
});

final youtubeSubscriptionsProvider =
    FutureProvider<List<PotvYoutubeSubscription>>((ref) {
  return ref.read(youtubeSubscriptionRepositoryProvider).all();
});

class YoutubeSubscriptionRepository {
  static const _key = 'potv_youtube_subscriptions_v1';

  const YoutubeSubscriptionRepository();

  Future<List<PotvYoutubeSubscription>> all() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((item) => PotvYoutubeSubscription.fromJson(
                Map<String, dynamic>.from(item),
              ))
          .where((item) => item.channelId.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<bool> isSubscribed(String channelId) async {
    return (await all()).any((item) => item.channelId == channelId);
  }

  Future<void> subscribe(PotvYoutubeSubscription subscription) async {
    final items = [...await all()];
    final index = items.indexWhere((item) => item.channelId == subscription.channelId);
    if (index >= 0) {
      items[index] = subscription;
    } else {
      items.add(subscription);
    }
    await _save(items);
  }

  Future<void> unsubscribe(String channelId) async {
    final items = [...await all()]..removeWhere((item) => item.channelId == channelId);
    await _save(items);
  }

  Future<int> importFromPicker() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv', 'json'],
      allowMultiple: false,
      withData: false,
    );
    final path = result?.files.single.path;
    if (path == null) return 0;
    final file = File(path);
    final text = await file.readAsString();
    final lower = path.toLowerCase();
    final imported = lower.endsWith('.json')
        ? _parseJson(text)
        : _parseCsv(text);
    if (imported.isEmpty) return 0;

    final merged = <String, PotvYoutubeSubscription>{
      for (final item in await all()) item.channelId: item,
      for (final item in imported) item.channelId: item,
    };
    await _save(merged.values.toList(growable: false));
    return imported.length;
  }

  Future<void> _save(List<PotvYoutubeSubscription> items) async {
    items.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode([for (final item in items) item.toJson()]),
    );
  }

  List<PotvYoutubeSubscription> _parseJson(String raw) {
    dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return const [];
    }

    final output = <String, PotvYoutubeSubscription>{};
    void visit(dynamic value) {
      if (value is List) {
        for (final item in value) visit(item);
        return;
      }
      if (value is! Map) return;
      final map = Map<String, dynamic>.from(value);
      final channelId = _findChannelId(map);
      if (channelId != null) {
        final title = _findTitle(map) ?? channelId;
        output[channelId] = PotvYoutubeSubscription(
          channelId: channelId,
          title: title,
        );
      }
      for (final child in map.values) {
        if (child is Map || child is List) visit(child);
      }
    }

    visit(decoded);
    return output.values.toList(growable: false);
  }

  List<PotvYoutubeSubscription> _parseCsv(String raw) {
    final lines = const LineSplitter().convert(raw);
    if (lines.isEmpty) return const [];
    final header = _csvRow(lines.first).map((v) => v.toLowerCase()).toList();
    int findColumn(List<String> names) {
      for (var i = 0; i < header.length; i++) {
        if (names.any((name) => header[i].contains(name))) return i;
      }
      return -1;
    }

    final idIndex = findColumn(['channel id', 'channelid', 'id del canal']);
    final urlIndex = findColumn(['channel url', 'url del canal', 'url']);
    final titleIndex = findColumn(['channel title', 'channel name', 'nombre del canal', 'title']);
    final output = <String, PotvYoutubeSubscription>{};

    for (final line in lines.skip(1)) {
      if (line.trim().isEmpty) continue;
      final row = _csvRow(line);
      String? channelId;
      if (idIndex >= 0 && idIndex < row.length) {
        channelId = _channelIdFromText(row[idIndex]);
      }
      if (channelId == null && urlIndex >= 0 && urlIndex < row.length) {
        channelId = _channelIdFromText(row[urlIndex]);
      }
      if (channelId == null) continue;
      final title = titleIndex >= 0 && titleIndex < row.length && row[titleIndex].trim().isNotEmpty
          ? row[titleIndex].trim()
          : channelId;
      output[channelId] = PotvYoutubeSubscription(
        channelId: channelId,
        title: title,
      );
    }
    return output.values.toList(growable: false);
  }

  List<String> _csvRow(String line) {
    final cells = <String>[];
    final buffer = StringBuffer();
    var quoted = false;
    for (var i = 0; i < line.length; i++) {
      final char = line[i];
      if (char == '"') {
        if (quoted && i + 1 < line.length && line[i + 1] == '"') {
          buffer.write('"');
          i++;
        } else {
          quoted = !quoted;
        }
      } else if (char == ',' && !quoted) {
        cells.add(buffer.toString().trim());
        buffer.clear();
      } else {
        buffer.write(char);
      }
    }
    cells.add(buffer.toString().trim());
    return cells;
  }

  String? _findChannelId(Map<String, dynamic> map) {
    for (final entry in map.entries) {
      final key = entry.key.toLowerCase().replaceAll('_', ' ');
      if (key.contains('channel') && key.contains('id')) {
        final id = _channelIdFromText(entry.value?.toString() ?? '');
        if (id != null) return id;
      }
    }
    for (final entry in map.entries) {
      final key = entry.key.toLowerCase();
      if (key.contains('url')) {
        final id = _channelIdFromText(entry.value?.toString() ?? '');
        if (id != null) return id;
      }
    }
    return null;
  }

  String? _findTitle(Map<String, dynamic> map) {
    for (final key in const ['title', 'name', 'channel title', 'channel_title']) {
      final value = map[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  String? _channelIdFromText(String value) {
    final match = RegExp(r'UC[A-Za-z0-9_-]{20,30}').firstMatch(value);
    return match?.group(0);
  }
}
