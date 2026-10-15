import 'package:flutter_test/flutter_test.dart';
import 'package:potv/core/security/media_url_logging.dart';

void main() {
  test('diagnostics never include signed CDN path or query tokens', () {
    final safe = safeMediaUrlForLog(Uri.parse(
      'https://cdn.example:8443/private/secret-abc/video?token=secret-xyz',
    ));
    expect(safe, 'https://cdn.example:8443/[redacted]');
    expect(safe, isNot(contains('secret')));
  });
  test('non-HTTP media references are never logged raw', () {
    expect(safeMediaUrlForLog(Uri.parse('file:///private/secret.mp4')),
        '[media-url-redacted]');
  });
  test('player errors redact signed URLs and bearer tokens', () {
    final error = safePlaybackErrorForLog(
      'media https://cdn.example/play?token=abc123 authorization=secret999',
    );
    expect(error, isNot(contains('cdn.example')));
    expect(error, isNot(contains('abc123')));
    expect(error, isNot(contains('secret999')));
  });

}
