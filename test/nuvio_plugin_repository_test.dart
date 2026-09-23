import 'package:flutter_test/flutter_test.dart';
import 'package:potv/data/plugins/nuvio_plugin_repository.dart';

void main() {
  test('parses Nuvio-compatible repository manifest', () {
    final parsed = NuvioPluginRepository.parseManifest(
      Uri.parse('https://example.test/manifest.json'),
      {
        'name': 'Demo Repo',
        'scrapers': [
          {
            'id': 'demo',
            'name': 'Demo Provider',
            'version': '1.2.3',
            'filename': 'providers/demo.js',
            'supportedTypes': ['movie', 'anime'],
            'enabled': true,
          },
        ],
      },
    );

    expect(parsed.name, 'Demo Repo');
    expect(parsed.plugins, hasLength(1));
    final plugin = parsed.plugins.single;
    expect(plugin.scriptUri.toString(), 'https://example.test/providers/demo.js');
    expect(plugin.supportedMediaTypes, containsAll(['movie', 'anime', 'tv']));
    expect(plugin.enabled, isTrue);
  });

  test('new user-installed plugins are enabled even if manifest defaults to off', () {
    final parsed = NuvioPluginRepository.parseManifest(
      Uri.parse('https://example.test/manifest.json'),
      {
        'name': 'Demo Repo',
        'scrapers': [
          {
            'id': 'disabled-upstream',
            'name': 'Disabled upstream',
            'version': '1',
            'filename': 'providers/disabled.js',
            'supportedTypes': ['movie'],
            'enabled': false,
          },
        ],
      },
    );

    expect(parsed.plugins.single.enabled, isTrue);
  });

  test('rejects repository without usable plugins', () {
    expect(
      () => NuvioPluginRepository.parseManifest(
        Uri.parse('https://example.test/manifest.json'),
        {'name': 'Empty', 'scrapers': []},
      ),
      throwsFormatException,
    );
  });
}
