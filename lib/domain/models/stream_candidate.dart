enum PlaybackBackend { native, webView, external }

class ExternalSubtitleTrack {
  final Uri uri;
  final String? language;
  final String? label;
  final String? mimeType;

  const ExternalSubtitleTrack({
    required this.uri,
    this.language,
    this.label,
    this.mimeType,
  });
}

class StreamCandidate {
  final String id;
  final String label;
  final Uri uri;
  final String? language;
  final String? quality;
  final PlaybackBackend backend;
  final Map<String, String> headers;
  final Uri? externalAudioUri;
  final List<ExternalSubtitleTrack> subtitles;
  final Set<String> allowedHosts;
  final bool directWebView;

  const StreamCandidate({
    required this.id,
    required this.label,
    required this.uri,
    this.language,
    this.quality,
    this.backend = PlaybackBackend.native,
    this.headers = const {},
    this.externalAudioUri,
    this.subtitles = const [],
    this.allowedHosts = const {},
    this.directWebView = false,
  });
}
