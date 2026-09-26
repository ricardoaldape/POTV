import 'dart:math' as math;

import '../models/stream_candidate.dart';

class StreamCandidateScore {
  final int total;
  final List<String> reasons;

  const StreamCandidateScore(this.total, this.reasons);
}

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
      if (current == null || analyze(candidate).total > analyze(current).total) {
        deduped[key] = candidate;
      }
    }

    final ranked = deduped.values.toList();
    final originalOrder = <String, int>{
      for (var i = 0; i < ranked.length; i++) ranked[i].id: i,
    };

    ranked.sort((a, b) {
      final byScore = analyze(b).total.compareTo(analyze(a).total);
      if (byScore != 0) return byScore;
      return (originalOrder[a.id] ?? 0).compareTo(originalOrder[b.id] ?? 0);
    });
    return ranked;
  }

  int score(StreamCandidate candidate) => analyze(candidate).total;

  StreamCandidateScore analyze(StreamCandidate candidate) {
    var total = switch (candidate.backend) {
      PlaybackBackend.native => 100,
      PlaybackBackend.webView => 45,
      PlaybackBackend.external => 10,
    };
    final reasons = <String>[
      switch (candidate.backend) {
        PlaybackBackend.native => 'reproducción nativa +100',
        PlaybackBackend.webView => 'webview +45',
        PlaybackBackend.external => 'externa +10',
      },
    ];

    final raw = [
      candidate.label,
      candidate.uri.toString(),
      candidate.language,
      candidate.quality,
    ].whereType<String>().join(' ').toLowerCase();
    final text = _fold(raw);

    if (_containsAny(text, const [
      'latino',
      'castellano',
      'espanol',
      'spanish',
      'es-es',
      'es-mx',
      'es-419',
    ])) {
      total += 100;
      reasons.add('audio/español +100');
    }

    if (_containsAny(text, const [
      'multi-audio',
      'multi audio',
      'dual-audio',
      'dual audio',
      'multi-subs',
      'multi subs',
    ])) {
      total += 50;
      reasons.add('multi audio/subs +50');
    }

    if (_containsAny(text, const ['1080p', '2160p', '4k'])) {
      total += 30;
      reasons.add('1080p/4K +30');
    } else if (text.contains('720p')) {
      total += 12;
      reasons.add('720p +12');
    }

    if (_containsAny(text, const [
      'hebsub',
      'subs-fr',
      'french',
      'fr-fr',
      'francais',
      'german',
      'de-de',
      'deutsch',
      'italian',
      'it-it',
      'italiano',
      'russian',
      'ru-ru',
      'portuguese',
      'pt-br',
      'pt-pt',
      'turkish',
      'tr-tr',
      'arabic',
      'ar-sa',
      'hebrew',
      'he-il',
    ])) {
      total -= 50;
      reasons.add('idioma no preferido -50');
    }

    if (candidate.subtitles.any((track) => _isSpanish(track.language))) {
      total += 10;
      reasons.add('subtítulos ES +10');
    }

    if (candidate.headers.isEmpty) {
      total += 2;
      reasons.add('sin headers especiales +2');
    }

    return StreamCandidateScore(total, reasons);
  }

  bool _containsAny(String text, List<String> values) {
    return values.any(text.contains);
  }

  bool _isSpanish(String? language) {
    if (language == null) return false;
    final value = _fold(language);
    return value == 'es' ||
        value.startsWith('es-') ||
        value.contains('spanish') ||
        value.contains('espanol') ||
        value.contains('latino') ||
        value.contains('castellano');
  }

  String _fold(String input) {
    return input
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ü', 'u')
        .replaceAll('ñ', 'n')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
