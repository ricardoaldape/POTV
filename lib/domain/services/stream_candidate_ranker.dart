import '../models/stream_candidate.dart';

class StreamCandidateRanker {
  const StreamCandidateRanker();

  List<StreamCandidate> rank(Iterable<StreamCandidate> candidates) {
    final deduped = <String, StreamCandidate>{};

    for (final candidate in candidates) {
      final key = [
        candidate.backend.name,
        candidate.uri.toString(),
        candidate.language ?? '',
      ].join('|');

      final current = deduped[key];
      if (current == null || score(candidate) > score(current)) {
        deduped[key] = candidate;
      }
    }

    final ranked = deduped.values.toList();
    ranked.sort((a, b) => score(b).compareTo(score(a)));
    return ranked;
  }

  int score(StreamCandidate candidate) {
    var total = switch (candidate.backend) {
      PlaybackBackend.native => 100,
      PlaybackBackend.webView => 55,
      PlaybackBackend.external => 20,
    };

    final language = [
      candidate.language,
      candidate.label,
    ].whereType<String>().join(' ').toLowerCase();

    if (language.contains('es-mx') ||
        language.contains('latino') ||
        language.contains('latin')) {
      total += 55;
    } else if (language.contains('español') ||
        language.contains('spanish') ||
        language.contains(' castellano')) {
      total += 45;
    } else if (language.contains('es')) {
      total += 20;
    }

    final quality = [
      candidate.quality,
      candidate.label,
    ].whereType<String>().join(' ').toLowerCase();

    if (quality.contains('2160') || quality.contains('4k')) {
      total += 40;
    } else if (quality.contains('1080')) {
      total += 34;
    } else if (quality.contains('720')) {
      total += 24;
    } else if (quality.contains('480')) {
      total += 12;
    }

    if (candidate.headers.isEmpty) total += 2;
    return total;
  }
}
