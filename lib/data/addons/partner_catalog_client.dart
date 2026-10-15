import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'verified_partner_catalog.dart';

final partnerCatalogClientProvider = Provider<PartnerCatalogClient>((ref) {
  return PartnerCatalogClient(Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 6),
      receiveTimeout: const Duration(seconds: 12),
      headers: const {
        'Accept': 'application/json',
        'User-Agent': 'POTV/1.0 (Android)',
      },
    ),
  ));
});

class PartnerCatalog {
  final String id;
  final String name;
  final String type;
  final Uri manifestUri;

  const PartnerCatalog({
    required this.id,
    required this.name,
    required this.type,
    required this.manifestUri,
  });
}

class PartnerCatalogMedia {
  final String id;
  final String title;
  final String type;
  final String? year;
  final String? description;
  final Uri? poster;
  final int? tmdbId;

  const PartnerCatalogMedia({
    required this.id,
    required this.title,
    required this.type,
    required this.year,
    required this.description,
    required this.poster,
    required this.tmdbId,
  });
}

/// Reads only the public Stremio catalog and meta resources from a user-
/// selected partner manifest. This is metadata discovery, NOT video access.
class PartnerCatalogClient {
  final Dio dio;

  const PartnerCatalogClient(this.dio);

  Future<List<PartnerCatalog>> catalogs(VerifiedPartnerAddon addon) async {
    if (!addon.offersCatalog) return const [];
    final response = await dio.getUri<Object?>(
      addon.manifestUri,
      options: Options(responseType: ResponseType.json),
    );
    return parseCatalogs(response.data, addon.manifestUri);
  }

  Future<List<PartnerCatalogMedia>> listings(PartnerCatalog catalog) async {
    final uri = catalog.manifestUri.resolve(
      'catalog/${Uri.encodeComponent(catalog.type)}/'
      '${Uri.encodeComponent(catalog.id)}.json',
    );
    final response = await dio.getUri<Object?>(
      uri,
      options: Options(responseType: ResponseType.json),
    );
    return parseMedia(response.data, catalog.type);
  }

  static List<PartnerCatalog> parseCatalogs(
    Object? raw,
    Uri manifestUri,
  ) {
    if (manifestUri.scheme != 'https' ||
        manifestUri.host.isEmpty ||
        manifestUri.userInfo.isNotEmpty) {
      return const [];
    }
    if (raw is! Map || raw['catalogs'] is! List) return const [];

    final seen = <String>{};
    final result = <PartnerCatalog>[];
    for (final item in raw['catalogs'] as List) {
      if (item is! Map) continue;
      final type = item['type']?.toString().trim() ?? '';
      final id = item['id']?.toString().trim() ?? '';
      if (!{'movie', 'series', 'anime', 'tv', 'music'}.contains(type) ||
          id.isEmpty || id.length > 100 || id.contains('/') ||
          id.contains('..') || !seen.add('$type:$id')) {
        continue;
      }
      final extras = item['extra'];
      // Some catalogs require per-account configuration or a search term.
      // Avoid promising they work without those parameters.
      if (extras is List && extras.any(
        (x) => x is Map && x['isRequired'] == true,
      )) {
        continue;
      }
      final name = item['name']?.toString().trim();
      result.add(PartnerCatalog(
        id: id,
        name: (name == null || name.isEmpty) ? id : name,
        type: type,
        manifestUri: manifestUri,
      ));
      if (result.length >= 60) break;
    }
    return List.unmodifiable(result);
  }

  static List<PartnerCatalogMedia> parseMedia(Object? raw, String type) {
    if (raw is! Map || raw['metas'] is! List) return const [];
    final result = <PartnerCatalogMedia>[];
    final seen = <String>{};
    for (final item in raw['metas'] as List) {
      if (item is! Map) continue;
      final title = item['name']?.toString().trim() ?? '';
      final id = item['id']?.toString().trim() ?? '';
      if (title.isEmpty || id.isEmpty || !seen.add(id)) continue;
      final poster = Uri.tryParse(item['poster']?.toString() ?? '');
      final text = item['description']?.toString().trim();
      final year = item['year']?.toString() ??
          item['releaseInfo']?.toString();
      final rawTmdb = item['moviedb_id'];
      result.add(PartnerCatalogMedia(
        id: id,
        title: title,
        type: type,
        year: (year == null || year.trim().isEmpty) ? null : year,
        description: (text == null || text.isEmpty) ? null : text,
        poster: poster != null &&
                poster.scheme == 'https' &&
                poster.host.isNotEmpty &&
                poster.userInfo.isEmpty
            ? poster
            : null,
        tmdbId: rawTmdb is int
            ? rawTmdb
            : int.tryParse(rawTmdb?.toString() ?? ''),
      ));
      if (result.length >= 100) break;
    }
    return List.unmodifiable(result);
  }
}
