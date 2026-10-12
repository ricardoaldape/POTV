import 'package:media_kit/media_kit.dart';

/// Respect explicit stream audio language and prefer a real Latino track,
/// then any Spanish track. Do not infer a track's language from its index.
class PlaybackLanguageSelector {
  const PlaybackLanguageSelector();

  int _spanishScore(String? language, String? name) {
    final text = '${language ?? ''} ${name ?? ''}'.toLowerCase();
    if (RegExp(r'(^|[^a-z])(es-mx|es_419|es-419|latino|latam)([^a-z]|$)')
        .hasMatch(text)) return 3;
    if (RegExp(r'(^|[^a-z])(es|spa|spanish|espanol|español|castellano)([^a-z]|$)')
        .hasMatch(text)) return 2;
    return 0;
  }

  AudioTrack? preferredAudio(
    List<AudioTrack> tracks, {
    String preferredLanguage = 'es-419',
  }) {
    final preference = preferredLanguage.toLowerCase();
    if (preference == 'original') return null;

    AudioTrack? best;
    var bestScore = 0;
    for (final track in tracks) {
      if (track.id == 'auto' || track.id == 'no') continue;
      final text = '${track.language ?? ''} ${track.title ?? ''}'.toLowerCase();
      final score = preference.startsWith('en')
          ? (RegExp(r'(^|[^a-z])(en|eng|english)([^a-z]|$)').hasMatch(text)
              ? 3
              : 0)
          : _spanishScore(track.language, track.title);
      if (score > bestScore) {
        best = track;
        bestScore = score;
      }
    }
    return best;
  }

  bool isSpanishAudio({AudioTrack? track, String? streamLanguage}) =>
      _spanishScore(track?.language ?? streamLanguage, track?.title) > 0;

  SubtitleTrack? preferredEmbeddedSubtitle(List<SubtitleTrack> tracks) {
    SubtitleTrack? best;
    var bestScore = 0;
    for (final track in tracks) {
      if (track.id == 'auto' || track.id == 'no') continue;
      final score = _spanishScore(track.language, track.title);
      if (score > bestScore) {
        best = track;
        bestScore = score;
      }
    }
    return best;
  }
}
