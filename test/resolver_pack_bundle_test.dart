import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:potv/core/local/resolver_pack_bundle.dart';
import 'package:potv/data/addons/stremio_addon_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SecretStore implements AddonSecretStore {
  final values = <String, String>{};
  @override
  Future<void> write(String key, String value) async { values[key] = value; }
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> delete(String key) async { values.remove(key); }
}

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

    final secrets = _SecretStore();
    final repository = StremioAddonRepository(secrets: secrets);
    final first = await ResolverPackBundle.importJson(pack, addonRepository: repository);
    final second = await ResolverPackBundle.importJson(pack, addonRepository: repository);

    expect(first.httpSourcesAdded, 1);
    expect(first.addonsAdded, 1);
    expect(second.totalAdded, 0);

    final exported = jsonDecode(await ResolverPackBundle.exportJson())
        as Map<String, dynamic>;
    expect(exported['format'], 'potv-resolver-pack');
    expect(exported['http_sources'], hasLength(1));
    expect(exported['stremio_addons'], isEmpty,
        reason: 'Private addon URLs are not exported to plain JSON');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('potv_stremio_addons'), isNot(contains('manifest_uri')));
    expect(secrets.values.length, 1);
  });

  test('rejects invalid resolver pack format', () async {
    expect(
      () => ResolverPackBundle.importJson('{"format":"other","version":1}'),
      throwsFormatException,
    );
  });
}
