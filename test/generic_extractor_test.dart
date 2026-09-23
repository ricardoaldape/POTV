import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:potv/config/extractors_config.dart';
import 'package:potv/data/extractors/generic_extractor.dart';

void main() {
  test('default extractor configuration is empty', () {
    expect(ExtractorsConfig.configs, isEmpty);
  });

  test('regexDirect extracts direct media URLs', () async {
    final dio = _dioFor((options) {
      return '<video src="https://cdn.example.test/video-1080.m3u8"></video>';
    });
    final extractor = GenericExtractor(
      const ExtractorConfig(
        name: 'Generic direct',
        domains: ['embed.example.test'],
        type: ExtractorType.regexDirect,
        pattern: r'src="([^"]+)"',
      ),
      dio: dio,
    );

    final streams =
        await extractor.extract('https://embed.example.test/watch/1');

    expect(streams, hasLength(1));
    expect(
      streams.single.uri.toString(),
      'https://cdn.example.test/video-1080.m3u8',
    );
    expect(streams.single.quality, '1080p');
  });

  test('regexFromScript only scans script contents', () async {
    final dio = _dioFor((options) {
      return '''
        <div>file: "https://ignored.example.test/not-a-script.m3u8"</div>
        <script>file: "https://cdn.example.test/from-script.m3u8";</script>
      ''';
    });
    final extractor = GenericExtractor(
      const ExtractorConfig(
        name: 'Script extractor',
        domains: ['embed.example.test'],
        type: ExtractorType.regexFromScript,
        pattern: r'file\s*:\s*"([^"]+)"',
      ),
      dio: dio,
    );

    final streams =
        await extractor.extract('https://embed.example.test/watch/2');

    expect(streams, hasLength(1));
    expect(
      streams.single.uri.toString(),
      'https://cdn.example.test/from-script.m3u8',
    );
  });

  test('iframeFollow resolves iframe and applies referer', () async {
    String? iframeReferer;
    final dio = _dioFor((options) {
      if (options.uri.path == '/watch/3') {
        return '<iframe src="/frame/3"></iframe>';
      }
      iframeReferer = options.headers['Referer']?.toString();
      return 'file: "https://cdn.example.test/from-frame.mp4"';
    });
    final extractor = GenericExtractor(
      const ExtractorConfig(
        name: 'Iframe extractor',
        domains: ['embed.example.test'],
        type: ExtractorType.iframeFollow,
        pattern: r'file\s*:\s*"([^"]+)"',
      ),
      dio: dio,
    );

    final streams =
        await extractor.extract('https://embed.example.test/watch/3');

    expect(streams, hasLength(1));
    expect(
      streams.single.uri.toString(),
      'https://cdn.example.test/from-frame.mp4',
    );
    expect(iframeReferer, 'https://embed.example.test/watch/3');
  });

  test('base64Decode decodes media URL', () async {
    final encoded = base64.encode(
      utf8.encode('https://cdn.example.test/base64-video.m3u8'),
    );
    final dio = _dioFor((options) => '<div data-video="$encoded"></div>');
    final extractor = GenericExtractor(
      const ExtractorConfig(
        name: 'Base64 extractor',
        domains: ['embed.example.test'],
        type: ExtractorType.base64Decode,
        pattern: r'data-video="([^"]+)"',
      ),
      dio: dio,
    );

    final streams =
        await extractor.extract('https://embed.example.test/watch/4');

    expect(streams, hasLength(1));
    expect(
      streams.single.uri.toString(),
      'https://cdn.example.test/base64-video.m3u8',
    );
  });

  test('customHeaders sends configured headers', () async {
    String? userAgent;
    String? referer;
    final dio = _dioFor((options) {
      userAgent = options.headers['User-Agent']?.toString();
      referer = options.headers['Referer']?.toString();
      return 'url="https://cdn.example.test/header-video.m3u8"';
    });
    final extractor = GenericExtractor(
      const ExtractorConfig(
        name: 'Header extractor',
        domains: ['embed.example.test'],
        type: ExtractorType.customHeaders,
        pattern: r'url="([^"]+)"',
        headers: {
          'User-Agent': 'POTV-Test-Agent',
          'Referer': 'https://ref.example.test/',
        },
      ),
      dio: dio,
    );

    final streams =
        await extractor.extract('https://embed.example.test/watch/5');

    expect(streams, hasLength(1));
    expect(userAgent, 'POTV-Test-Agent');
    expect(referer, 'https://ref.example.test/');
    expect(streams.single.headers['User-Agent'], 'POTV-Test-Agent');
  });
}

Dio _dioFor(String Function(RequestOptions options) responseBody) {
  final dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        handler.resolve(
          Response<String>(
            requestOptions: options,
            statusCode: 200,
            data: responseBody(options),
          ),
        );
      },
    ),
  );
  return dio;
}
