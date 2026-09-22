import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:potv/core/local/resolver_pack_bundle.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('imports resolver pack and deduplicates equivalent endpoints', () async {
    final pack = jsonEncode({
      'format': 'potv-resolver-pack',
      'version': 1,
      'http_sources': [
        {
          'id': 'http-1',
          'name': 'Resolver Demo',
          'endpoint': 'https://resolver.example/api/',
          'enabled': true,
        },
        {
          'id': 'http-2',
          'name': 'Resolver Demo duplicate',
          'endpoint': 'https://resolver.example/api',
          'enabled': true,
        },
      ],
      'stremio_addons': [
        {
          'id': 'addon-1',
          'name': 'Addon Demo',
          'manifest_uri': 'https://addon.example/manifest.json',
          'enabled': true,
        },
      ],
    });

    final first = await ResolverPackBundle.importJson(pack);
    final second = await ResolverPackBundle.importJson(pack);

    expect(first.httpSourcesAdded, 1);
    expect(first.addonsAdded, 1);
    expect(second.totalAdded, 0);

    final exported = jsonDecode(await ResolverPackBundle.exportJson())
        as Map<String, dynamic>;
    expect(exported['format'], 'potv-resolver-pack');
    expect(exported['http_sources'], hasLength(1));
    expect(exported['stremio_addons'], hasLength(1));
  });

  test('rejects invalid resolver pack format', () async {
    expect(
      () => ResolverPackBundle.importJson('{"format":"other","version":1}'),
      throwsFormatException,
    );
  });
}
