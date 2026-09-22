import '../models/stream_candidate.dart';

abstract interface class SourceResolver {
  Future<List<StreamCandidate>> resolve({
    required String mediaType,
    required String mediaId,
    String? externalId,
    String? title,
    String? year,
    int? season,
    int? episode,
  });
}
