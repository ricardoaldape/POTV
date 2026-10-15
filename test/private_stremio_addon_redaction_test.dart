import 'package:flutter_test/flutter_test.dart';
import 'package:potv/core/security/media_url_logging.dart';
import 'package:potv/data/addons/stremio_addon_client.dart';
import 'package:potv/data/addons/stremio_protocol.dart';
import 'package:potv/domain/models/stremio_addon_config.dart';
import 'package:dio/dio.dart';

void main() {
  const fakeToken = 'PRIVATE_TEST_TOKEN_NOT_REAL';
  final privateManifest = Uri.parse(
    'https://addon.example/%7B%22auth_token%22%3A%22'
    '$fakeToken%22%7D/manifest.json',
  );

  test('authenticated addon configuration works with standard Stremio URL',
      () {
    final addon = StremioAddonConfig(
      id: 'personal',
      name: 'Personal addon',
      manifestUri: privateManifest,
    );
    final manifest = StremioAddonClient(Dio())
        .normalizeManifestUri(addon.manifestUri);
    expect(manifest, privateManifest);
    final stream = StremioProtocol.streamUri(
      addon: addon,
      type: 'movie',
      itemId: 'tt1254207',
    );
    expect(stream.host, privateManifest.host);
    expect(stream.path, contains('auth_token'));
    expect(stream.toString(), contains(fakeToken));
    expect(stream.pathSegments.last, 'tt1254207.json');
  });

  test('private addon manifest and stream URLs are safely redacted', () {
    final addon = StremioAddonConfig(
      id: 'personal',
      name: 'Personal addon',
      manifestUri: privateManifest,
    );
    final resolved = StremioProtocol.streamUri(
      addon: addon,
      type: 'series',
      itemId: 'tt001:2:4',
    );
    for (final uri in [privateManifest, resolved]) {
      final safe = safeMediaUrlForLog(uri);
      expect(safe, 'https://addon.example/[redacted]');
      expect(safe, isNot(contains(fakeToken)));
      expect(safe, isNot(contains('auth_token')));
    }
  });

  test('decoder/manifest errors redact URLs carrying private auth', () {
    final message =
        'Stremio request failed: ${privateManifest.toString()} status 401';
    final safe = safePlaybackErrorForLog(message);
    expect(safe, isNot(contains(fakeToken)));
    expect(safe, isNot(contains('auth_token')));
    expect(safe, contains('[URL oculta]'));
  });
}
