/// Displays only a media URL's origin in diagnostics. Signed CDN URLs may
/// carry API tokens in query parameters *or path segments*, so neither may
/// be persisted in logs or screenshots used for support.
String safeMediaUrlForLog(Uri uri) {
  final scheme = uri.scheme.toLowerCase();
  if ((scheme != 'http' && scheme != 'https') || uri.host.isEmpty) {
    return '[media-url-redacted]';
  }
  final port = uri.hasPort ? ':\u0024{uri.port}' : '';
  return '\u0024scheme://\u0024{uri.host}\u0024port/[redacted]';
}
