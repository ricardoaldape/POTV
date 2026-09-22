import '../models/stream_candidate.dart';

abstract interface class SourceResolver {
  Future<List<StreamCandidate>> resolve({
    required String mediaType,
    required String mediaId,
    int? season,
    int? episode,
  });
}
