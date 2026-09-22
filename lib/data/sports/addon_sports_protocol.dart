import '../../domain/models/addon_sports_item.dart';
import '../../domain/models/stremio_addon_config.dart';

class AddonSportsProtocol {
  const AddonSportsProtocol._();

  static List<AddonSportsItem> parseCatalog({
    required StremioAddonConfig addon,
    required String fallbackType,
    required Object? raw,
  }) {
    if (raw is! Map<String, dynamic>) return const [];
    final metas = raw['metas'];
    if (metas is! List) return const [];

    final result = <AddonSportsItem>[];
    for (final value in metas) {
      if (value is! Map<String, dynamic>) continue;

      final id = _text(value['id']);
      final type = _text(value['type']) ?? fallbackType;
      final name = _text(value['name']);
      if (id == null || name == null) continue;

      final genres = value['genres'];
      final genre = genres is List && genres.isNotEmpty
          ? _text(genres.first)
          : null;
      final description = _text(value['description']);
      final posterText = _text(value['poster']);
      final combined =
          '${name.toLowerCase()} ${description?.toLowerCase() ?? ''}';

      result.add(
        AddonSportsItem(
          addon: addon,
          id: id,
          type: type,
          name: name,
          description: description,
          poster: posterText == null ? null : Uri.tryParse(posterText),
          genre: genre,
          isLive: combined.contains('live') ||
              combined.contains('en vivo') ||
              combined.contains('🔴'),
        ),
      );

      if (result.length >= 50) break;
    }

    return result;
  }

  static String? _text(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
}
