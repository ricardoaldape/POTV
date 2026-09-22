import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/addon_sports_item.dart';
import '../../domain/models/stremio_addon_config.dart';
import '../../domain/models/stream_candidate.dart';
import '../addons/stremio_addon_repository.dart';
import '../addons/stremio_protocol.dart';

final addonSportsRepositoryProvider = Provider<AddonSportsRepository>((ref) {
  return AddonSportsRepository(
    ref.read(stremioAddonRepositoryProvider),
    Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 18),
        headers: const {
          'Accept': 'application/json',
          'User-Agent': 'POTV/0.1 (Android)',
        },
      ),
    ),
  );
});

final addonSportsItemsProvider = FutureProvider.autoDispose
    .family<List<AddonSportsItem>, String>((ref, sport) {
  return ref.read(addonSportsRepositoryProvider).itemsForSport(sport);
});

class AddonSportsRepository {
  final StremioAddonRepository _addons;
  final Dio _dio;

  AddonSportsRepository(this._addons, this._dio);

  Future<List<AddonSportsItem>> itemsForSport(String sport) async {
    final addons = (await _addons.load())
        .where((addon) => addon.enabled)
        .toList(growable: false);
    if (addons.isEmpty) return const [];

    final batches = await Future.wait([
      for (final addon in addons) _itemsForAddon(addon, sport),
    ]);

    final seen = <String>{};
    final result = <AddonSportsItem>[];
    for (final batch in batches) {
      for (final item in batch) {
        final key = '${item.addon.id}:${item.type}:${item.id}';
        if (seen.add(key)) result.add(item);
      }
    }

    result.sort((a, b) {
      if (a.isLive != b.isLive) return a.isLive ? -1 : 1;
      return a.name.compareTo(b.name);
    });
    return result;
  }

  Future<List<StreamCandidate>> streamsFor(AddonSportsItem item) async {
    try {
      final uri = StremioProtocol.streamUri(
        addon: item.addon,
        type: item.type,
        itemId: item.id,
      );
      final response = await _dio.getUri<Object?>(
        uri,
        options: Options(responseType: ResponseType.json),
      );
      return StremioProtocol.parseStreams(
        addon: item.addon,
        raw: response.data,
      );
    } on DioException {
      return const [];
    } on FormatException {
      return const [];
    }
  }

  Future<List<AddonSportsItem>> _itemsForAddon(
    StremioAddonConfig addon,
    String sport,
  ) async {
    try {
      final manifestResponse = await _dio.getUri<Object?>(
        addon.manifestUri,
        options: Options(responseType: ResponseType.json),
      );
      final manifest = manifestResponse.data;
      if (manifest is! Map<String, dynamic>) return const [];
      if (!_supportsResource(manifest['resources'], 'catalog') ||
          !_supportsResource(manifest['resources'], 'stream')) {
        return const [];
      }

      final catalogsRaw = manifest['catalogs'];
      if (catalogsRaw is! List) return const [];

      final catalogs = <Map<String, dynamic>>[
        for (final value in catalogsRaw)
          if (value is Map<String, dynamic>) value,
      ];

      final genre = _genreForSport(sport);
      final selected = _selectCatalogs(catalogs, genre);
      if (selected.isEmpty) return const [];

      final batches = await Future.wait([
        for (final catalog in selected)
          _loadCatalog(
            addon,
            catalog,
            genre: genre,
          ),
      ]);

      final seen = <String>{};
      final result = <AddonSportsItem>[];
      for (final batch in batches) {
        for (final item in batch) {
          if (seen.add(item.id)) result.add(item);
          if (result.length >= 60) return result;
        }
      }
      return result;
    } on DioException {
      return const [];
    } on FormatException {
      return const [];
    }
  }

  List<Map<String, dynamic>> _selectCatalogs(
    List<Map<String, dynamic>> catalogs,
    String genre,
  ) {
    final normalizedGenre = _normalize(genre);
    final live = <Map<String, dynamic>>[];
    final sportSpecific = <Map<String, dynamic>>[];

    for (final catalog in catalogs) {
      final type = _text(catalog['type'])?.toLowerCase();
      if (type != 'tv' && type != 'channel' && type != 'series') continue;

      final id = _normalize(_text(catalog['id']) ?? '');
      final name = _normalize(_text(catalog['name']) ?? '');
      final haystack = '$id $name';

      if (haystack.contains('replay')) continue;

      if (haystack.contains('live') && !haystack.contains('upcoming')) {
        live.add(catalog);
      }

      final sportTokens = _sportTokens(normalizedGenre);
      if (sportTokens.any(haystack.contains) &&
          !haystack.contains('upcoming') &&
          !haystack.contains('network')) {
        sportSpecific.add(catalog);
      }
    }

    final result = <Map<String, dynamic>>[];
    if (live.isNotEmpty) result.add(live.first);

    for (final catalog in sportSpecific) {
      if (result.any((value) => value['id'] == catalog['id'])) continue;
      result.add(catalog);
      if (result.length >= 2) break;
    }

    if (result.isEmpty) {
      for (final catalog in catalogs) {
        final id = _normalize(_text(catalog['id']) ?? '');
        final name = _normalize(_text(catalog['name']) ?? '');
        if ('$id $name'.contains('sport')) {
          result.add(catalog);
          break;
        }
      }
    }

    return result;
  }

  Future<List<AddonSportsItem>> _loadCatalog(
    StremioAddonConfig addon,
    Map<String, dynamic> catalog, {
    required String genre,
  }) async {
    final type = _text(catalog['type']);
    final id = _text(catalog['id']);
    if (type == null || id == null) return const [];

    final supportsGenre = _catalogSupportsGenre(catalog, genre);
    final encodedType = Uri.encodeComponent(type);
    final encodedId = Uri.encodeComponent(id);
    final suffix = supportsGenre
        ? '/genre=${Uri.encodeComponent(genre)}.json'
        : '.json';

    final uri = addon.manifestUri.resolve(
      'catalog/$encodedType/$encodedId$suffix',
    );

    try {
      final response = await _dio.getUri<Object?>(
        uri,
        options: Options(responseType: ResponseType.json),
      );
      final raw = response.data;
      if (raw is! Map<String, dynamic>) return const [];
      final metas = raw['metas'];
      if (metas is! List) return const [];

      final result = <AddonSportsItem>[];
      for (final value in metas) {
        if (value is! Map<String, dynamic>) continue;
        final itemId = _text(value['id']);
        final itemType = _text(value['type']) ?? type;
        final name = _text(value['name']);
        if (itemId == null || name == null) continue;

        final genres = value['genres'];
        final genreText = genres is List && genres.isNotEmpty
            ? _text(genres.first)
            : null;
        final description = _text(value['description']);
        final combined =
            '${name.toLowerCase()} ${description?.toLowerCase() ?? ''}';

        result.add(
          AddonSportsItem(
            addon: addon,
            id: itemId,
            type: itemType,
            name: name,
            description: description,
            poster: Uri.tryParse(_text(value['poster']) ?? ''),
            genre: genreText,
            isLive: combined.contains('live') ||
                combined.contains('en vivo') ||
                combined.contains('🔴'),
          ),
        );
        if (result.length >= 50) break;
      }
      return result;
    } on DioException {
      return const [];
    }
  }

  bool _catalogSupportsGenre(
    Map<String, dynamic> catalog,
    String genre,
  ) {
    final extra = catalog['extra'];
    if (extra is! List) return false;

    for (final value in extra) {
      if (value is! Map) continue;
      if (_text(value['name']) != 'genre') continue;

      final options = value['options'];
      if (options is! List || options.isEmpty) return true;
      return options.any(
        (option) => _normalize(option.toString()) == _normalize(genre),
      );
    }
    return false;
  }

  bool _supportsResource(Object? raw, String resource) {
    if (raw is! List) return false;
    for (final value in raw) {
      if (value is String && value == resource) return true;
      if (value is Map && _text(value['name']) == resource) return true;
    }
    return false;
  }

  String _genreForSport(String sport) {
    switch (sport.toLowerCase()) {
      case 'soccer':
        return 'Football';
      case 'basketball':
        return 'Basketball';
      case 'american football':
        return 'American Football';
      case 'baseball':
        return 'Baseball';
      case 'ice hockey':
        return 'Hockey';
      case 'motorsport':
        return 'Motorsport';
      case 'tennis':
        return 'Tennis';
      case 'fighting':
        return 'MMA';
      default:
        return sport;
    }
  }

  List<String> _sportTokens(String normalizedGenre) {
    if (normalizedGenre == 'football') {
      return const ['football', 'soccer'];
    }
    if (normalizedGenre == 'american football') {
      return const ['american football', 'nfl'];
    }
    if (normalizedGenre == 'motorsport') {
      return const ['motorsport', 'motor', 'formula', 'f1', 'racing'];
    }
    if (normalizedGenre == 'mma') {
      return const ['mma', 'fight', 'combat', 'ufc'];
    }
    return [normalizedGenre];
  }

  String _normalize(String value) {
    var out = value.toLowerCase().trim();
    const replacements = <String, String>{
      'á': 'a',
      'é': 'e',
      'í': 'i',
      'ó': 'o',
      'ú': 'u',
      'ü': 'u',
      'ñ': 'n',
    };
    for (final entry in replacements.entries) {
      out = out.replaceAll(entry.key, entry.value);
    }
    return out;
  }

  String? _text(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
}
