/// Displays only a media URL's origin in diagnostics. Signed CDN URLs may
/// carry API tokens in query parameters *or path segments*, so neither may
/// be persisted in logs or screenshots used for support.
String safeMediaUrlForLog(Uri uri) {
  final scheme = uri.scheme.toLowerCase();
  if ((scheme != 'http' && scheme != 'https') || uri.host.isEmpty) {
    return '[media-url-redacted]';
  }
  final port = uri.hasPort ? ':${uri.port}' : '';
  return '$scheme://${uri.host}$port/[redacted]';
}

String safePlaybackErrorForLog(String message) {
  // Native decoders can include signed stream URLs and query tokens in
  // exception strings. None should be exposed in debug logs or UI.
  final redactedUrls = message.replaceAll(
    RegExp(r'https?://[^\s\\<>"\x27]+', caseSensitive: false),
    '[URL oculta]',
  );
  final redactedSecrets = redactedUrls.replaceAll(
    RegExp(
      r'(token|signature|api[_-]?key|authorization|bearer|secret)\s*[:=]\s*[^\s,;]+',
      caseSensitive: false,
    ),
    '[credencial oculta]',
  );
  return redactedSecrets.length <= 320
      ? redactedSecrets
      : '${redactedSecrets.substring(0, 320)}…';
}
