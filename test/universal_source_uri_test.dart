import 'package:flutter_test/flutter_test.dart';
import 'package:potv/data/sources/universal_source_installer.dart';

void main() {
  group('Partner Stremio manifests', () {
    test('normalizes a stremio:// partner addon share into HTTPS', () {
      final uri = UniversalSourceInstaller.normalizeUrl(
        'stremio://addon.example/manifest.json',
      );
      expect(uri.toString(), 'https://addon.example/manifest.json');
    });

    test('preserves token-bearing HTTPS addon paths without logging them', () {
      final uri = UniversalSourceInstaller.normalizeUrl(
        'stremio://addon.example/private-token/manifest.json',
      );
      expect(uri.pathSegments.last, 'manifest.json');
      expect(uri.scheme, 'https');
    });

    test('preserves ordinary HTTPS and M3U source links', () {
      expect(
        UniversalSourceInstaller.normalizeUrl(
          'https://provider.example/live/channel.m3u8',
        ).toString(),
        'https://provider.example/live/channel.m3u8',
      );
    });

    test('rejects malformed links and embedded userinfo', () {
      for (final url in [
        'stremio://',
        'stremio://name:password@addon.example/manifest.json',
        'javascript:alert(1)',
        'stremio:///manifest.json',
      ]) {
        expect(
          () => UniversalSourceInstaller.normalizeUrl(url),
          throwsFormatException,
          reason: 'URL must be rejected',
        );
      }
    });
  });
}
