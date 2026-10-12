import 'package:media_kit/media_kit.dart';

/// POTV prefers Latin American Spanish when a stream actually offers it.
/// Provider labels are not reliable evidence of language; use track metadata.
class SpanishTrackSelector {
  const SpanishTrackSelector._();

  static AudioTrack? preferredAudio(List<AudioTrack> tracks) =>
      _best<AudioTrack>(tracks, (track) => track.id, (track) => track.language,
          (track) => track.title);

  static SubtitleTrack? preferredSubtitle(List<SubtitleTrack> tracks) =>
      _best<SubtitleTrack>(tracks, (track) => track.id,
          (track) => track.language, (track) => track.title);

  static T? _best<T>(
    List<T> tracks,
    String Function(T) id,
    String? Function(T) language,
    String? Function(T) title,
  ) {
    T? best;
    var topScore = 0;
    for (final track in tracks) {
      if (id(track) == 'auto' || id(track) == 'no') continue;
      final value = [
        language(track) ?? '',
        title(track) ?? '',
      ].join(' ').toLowerCase().replaceAll('_', '-');
      final lang = (language(track) ?? '').toLowerCase().replaceAll('_', '-');
      final spanish = lang == 'es' ||
          lang == 'spa' ||
          lang.startsWith('es-') ||
          lang.startsWith('spa-') ||
          RegExp(r'\b(español|espanol|spanish|castellano)\b').hasMatch(value);
      if (!spanish) continue;
      var score = 30;
      if (RegExp(r'\b(latino|latina|latam|latinoamérica|latinoamerica|méxico|mexico)\b')
              .hasMatch(value) ||
          lang == 'es-419' ||
          lang == 'es-mx' ||
          lang == 'es-ar') {
        score += 50;
      }
      if (lang == 'es-es' || value.contains('castellano')) score -= 10;
      if (score > topScore) {
        best = track;
        topScore = score;
      }
    }
    return best;
  }
}
