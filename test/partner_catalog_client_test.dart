import 'package:flutter_test/flutter_test.dart';
import 'package:potv/data/addons/partner_catalog_client.dart';

void main() {
  final manifest = Uri.parse('https://catalog.example/stremio/manifest.json');

  test('parses safe partner catalog routes and skips required credentials', () {
    final catalog = PartnerCatalogClient.parseCatalogs({
      'catalogs': [
        {'id': 'popular', 'type': 'movie', 'name': 'Películas'},
        {'id': 'airing', 'type': 'anime', 'name': 'Anime al aire'},
        {'id': '../admin', 'type': 'movie', 'name': 'Unsafe'},
        {'id': 'search-only', 'type': 'series', 'name': 'Search',
         'extra': [{'name': 'search', 'isRequired': true}]},
        {'id': 'popular', 'type': 'movie', 'name': 'Duplicado'},
      ],
    }, manifest);

    expect(catalog, hasLength(2));
    expect(catalog.first.name, 'Películas');
    expect(catalog.first.type, 'movie');
    expect(catalog.last.type, 'anime');
    expect(catalog.last.manifestUri, manifest);
  });

  test('catalog media are metadata and preserve safe poster URLs', () {
    final items = PartnerCatalogClient.parseMedia({
      'metas': [
        {
          'id': 'tt1000001',
          'name': 'Película de ejemplo',
          'moviedb_id': 123,
          'year': '2000',
          'poster': 'https://images.example/poster.jpg',
          'description': 'Sinopsis de ejemplo',
        },
        {
          'id': 'tt1000002',
          'name': 'Película sin imagen',
          'poster': 'http://invalid.example/poster.jpg',
        },
        {'id': 'tt1000001', 'name': 'Duplicada'},
        {'id': '', 'name': 'Sin ID'},
      ],
    }, 'movie');

    expect(items, hasLength(2));
    expect(items.first.tmdbId, 123);
    expect(items.first.type, 'movie');
    expect(items.first.description, 'Sinopsis de ejemplo');
    expect(items.first.poster!.scheme, 'https');
    expect(items.last.poster, isNull);
  });

  test('rejects insecure catalog base and invalid responses', () {
    expect(
      PartnerCatalogClient.parseCatalogs(
        {'catalogs': [{'id': 'top', 'type': 'movie'}]},
        Uri.parse('http://catalog.example/manifest.json'),
      ),
      isEmpty,
    );
    expect(PartnerCatalogClient.parseMedia({'wrong': []}, 'series'), isEmpty);
  });
}
