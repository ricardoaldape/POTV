import '../models/stream_candidate.dart';

class ProviderResolveRequest {
  final String mediaType;
  final String mediaId;
  final String? externalId;
  final String? title;
  final String? year;
  final int? season;
  final int? episode;

  const ProviderResolveRequest({
    required this.mediaType,
    required this.mediaId,
    this.externalId,
    this.title,
    this.year,
    this.season,
    this.episode,
  });

  bool get isMovie => mediaType == 'movie';
  bool get isSeries => mediaType == 'tv';
  bool get isAnime => mediaType == 'anime';
}

abstract interface class ProviderResolver {
  String get id;
  String get displayName;
  int get priority;
  Set<String> get supportedMediaTypes;

  bool supports(ProviderResolveRequest request) {
    return supportedMediaTypes.contains(request.mediaType);
  }

  Future<List<StreamCandidate>> resolve(ProviderResolveRequest request);
}

class ProviderResolutionResult {
  final List<StreamCandidate> candidates;
  final int providersEligible;
  final int providersCompleted;
  final int providersFailed;

  const ProviderResolutionResult({
    required this.candidates,
    required this.providersEligible,
    required this.providersCompleted,
    required this.providersFailed,
  });
}
