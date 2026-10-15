import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Partner-supplied public Stremio manifests, verified independently before
/// bundling. A working manifest does NOT imply that it serves playable video.
final verifiedPartnerAddonsProvider =
    FutureProvider<List<VerifiedPartnerAddon>>((ref) async {
  final source = await rootBundle.loadString(
    'assets/partner_compatible_addons_kino.json',
  );
  return VerifiedPartnerAddon.parseCatalog(source);
});

class VerifiedPartnerAddon {
  final String id;
  final String name;
  final Uri manifestUri;
  final Set<String> resources;
  final Set<String> types;
  final Set<String> categories;

  const VerifiedPartnerAddon({
    required this.id,
    required this.name,
    required this.manifestUri,
    required this.resources,
    required this.types,
    required this.categories,
  });

  bool get offersStreams => resources.contains('stream');
  bool get offersSubtitles => resources.contains('subtitles');
  bool get offersCatalog => resources.contains('catalog');
  bool get supportsCurrentPlayback => offersStreams || offersSubtitles;

  /// Avoid claiming a catalog-only addon provides playable streams.
  String get capabilityLabel {
    if (offersStreams && offersSubtitles) {
      return 'Reproducción y subtítulos';
    }
    if (offersStreams) return 'Reproducción (según proveedor)';
    if (offersSubtitles) return 'Subtítulos';
    if (offersCatalog) return 'Catálogo de títulos (sin video)';
    return 'Información';
  }

  static List<VerifiedPartnerAddon> parseCatalog(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map || decoded['schema'] != 1 ||
        decoded['addons'] is! List) {
      throw const FormatException('Catálogo de complementos inválido.');
    }

    Set<String> texts(Object? value) {
      if (value is! List) return const {};
      return value
          .whereType<String>()
          .map((item) => item.trim().toLowerCase())
          .where((item) => item.isNotEmpty)
          .toSet();
    }

    final results = <VerifiedPartnerAddon>[];
    final seen = <String>{};
    for (final value in decoded['addons'] as List) {
      if (value is! Map) continue;
      final id = value['id']?.toString().trim() ?? '';
      final name = value['name']?.toString().trim() ?? '';
      final uri = Uri.tryParse(value['manifest']?.toString() ?? '');
      if (id.isEmpty || name.isEmpty || uri == null ||
          uri.scheme != 'https' || uri.host.isEmpty ||
          uri.userInfo.isNotEmpty || uri.hasFragment ||
          !uri.path.endsWith('/manifest.json') ||
          !seen.add(id)) {
        continue;
      }
      results.add(VerifiedPartnerAddon(
        id: id,
        name: name,
        manifestUri: uri,
        resources: texts(value['resources']),
        types: texts(value['types']),
        categories: texts(value['categories']),
      ));
      if (results.length >= 80) break;
    }
    return List.unmodifiable(results);
  }
}
