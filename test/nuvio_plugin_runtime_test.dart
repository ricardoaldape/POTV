import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:potv/data/plugins/nuvio_plugin_runtime.dart';
import 'package:potv/domain/models/nuvio_plugin_config.dart';

void main() {
  final plugin = NuvioPluginConfig(
    id: 'demo',
    repositoryName: 'Demo Repo',
    repositoryUri: Uri(scheme: 'https', host: 'example.test', path: '/manifest.json'),
    name: 'Demo',
    version: '1',
    scriptUri: Uri(scheme: 'https', host: 'example.test', path: '/demo.js'),
    supportedMediaTypes: {'movie', 'tv'},
  );

  test('normalizes plugin results into stream candidates', () {
    final raw = jsonEncode([
      {
        'name': 'Servidor A',
        'url': 'https://cdn.example.test/master.m3u8',
        'quality': '1080p',
        'language': 'Latino',
        'headers': {'X-Test': 'yes'},
        'behaviorHints': {
          'proxyHeaders': {
            'request': {'Referer': 'https://example.test/'},
          },
        },
      },
      {
        'name': 'Duplicado',
        'url': 'https://cdn.example.test/master.m3u8',
      },
    ]);

    final result = NuvioPluginRuntime.parseResults(plugin, raw);
    expect(result, hasLength(1));
    expect(result.single.label, 'Servidor A');
    expect(result.single.quality, '1080p');
    expect(result.single.language, 'Latino');
    expect(result.single.headers['X-Test'], 'yes');
    expect(result.single.headers['Referer'], 'https://example.test/');
  });
}
