enum ExtractorType {
  regexDirect,
  regexFromScript,
  iframeFollow,
  base64Decode,
  customHeaders,
}

class ExtractorConfig {
  final String name;
  final List<String> domains;
  final ExtractorType type;
  final String pattern;
  final Map<String, String>? headers;

  const ExtractorConfig({
    required this.name,
    required this.domains,
    required this.type,
    required this.pattern,
    this.headers,
  });

  bool matches(Uri uri) {
    if (uri.scheme != 'http' && uri.scheme != 'https') return false;
    final host = uri.host.toLowerCase();
    if (host.isEmpty) return false;

    for (final rawDomain in domains) {
      final domain = _normalizeDomain(rawDomain);
      if (domain == null) continue;
      if (host == domain || host.endsWith('.$domain')) return true;
    }
    return false;
  }

  String? _normalizeDomain(String value) {
    var candidate = value.trim().toLowerCase();
    if (candidate.isEmpty) return null;

    final parsed = Uri.tryParse(candidate);
    if (parsed != null && parsed.hasScheme && parsed.host.isNotEmpty) {
      candidate = parsed.host.toLowerCase();
    }

    while (candidate.startsWith('.')) {
      candidate = candidate.substring(1);
    }
    return candidate.isEmpty ? null : candidate;
  }
}

class ExtractorsConfig {
  const ExtractorsConfig._();

  static const List<ExtractorConfig> configs = [];
}
