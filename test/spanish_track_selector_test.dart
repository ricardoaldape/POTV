import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:potv/features/player/spanish_track_selector.dart';

void main() {
  test('prefers Latin Spanish over Castilian and generic Spanish', () {
    final tracks = <AudioTrack>[
      const AudioTrack('1', 'Original English', 'en'),
      const AudioTrack('2', 'Castellano', 'es-ES'),
      const AudioTrack('3', 'Español', 'es'),
      const AudioTrack('4', 'Español Latino', 'es-MX'),
    ];
    expect(SpanishTrackSelector.preferredAudio(tracks)?.id, '4');
  });

  test('returns null when stream does not offer Spanish audio', () {
    final tracks = <AudioTrack>[
      AudioTrack.auto(),
      const AudioTrack('1', 'English', 'en'),
      const AudioTrack('2', 'Japanese', 'ja'),
    ];
    expect(SpanishTrackSelector.preferredAudio(tracks), isNull);
  });

  test('prefers Spanish subtitle and ignores auto/disabled options', () {
    final tracks = <SubtitleTrack>[
      SubtitleTrack.auto(),
      SubtitleTrack.no(),
      const SubtitleTrack('3', 'English', 'en'),
      const SubtitleTrack('4', 'Español Latino', 'es-419'),
      const SubtitleTrack('5', 'Español España', 'es-ES'),
    ];
    expect(SpanishTrackSelector.preferredSubtitle(tracks)?.id, '4');
  });

  test('detects Spanish from title when language code is absent', () {
    final tracks = <SubtitleTrack>[
      const SubtitleTrack('3', 'Subtítulos Spanish', null),
      const SubtitleTrack('4', 'Español Latino', null),
    ];
    expect(SpanishTrackSelector.preferredSubtitle(tracks)?.id, '4');
  });

  test('does not assume unspecified language is Spanish', () {
    final tracks = <SubtitleTrack>[
      const SubtitleTrack('3', 'Forced', null),
      const SubtitleTrack('4', 'Default', null),
    ];
    expect(SpanishTrackSelector.preferredSubtitle(tracks), isNull);
  });
}
