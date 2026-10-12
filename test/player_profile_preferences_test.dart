import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:potv/features/player/player_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('player reads active profile playback preferences', () async {
    SharedPreferences.setMockInitialValues({
      'potv_active_profile_id': 'profile-2',
      'potv_user_profiles_v2': jsonEncode([
        {
          'id': 'profile-1',
          'preferences': {
            'audioLanguage': 'en',
            'subtitleLanguage': 'off',
            'autoplayNext': false,
          },
        },
        {
          'id': 'profile-2',
          'preferences': {
            'audioLanguage': 'es-419',
            'subtitleLanguage': 'es',
            'autoplayNext': true,
          },
        },
      ]),
    });

    final preferences = await PlayerPreferences.load();
    expect(preferences.audioLanguage, 'es-419');
    expect(preferences.subtitleLanguage, 'es');
    expect(preferences.autoplayNext, isTrue);
    expect(preferences.media3AudioPreference, 'spanish');
    expect(preferences.media3SubtitlePreference, 'whenNoSpanishAudio');
  });

  test('original audio and disabled subtitles map cleanly to Media3', () async {
    SharedPreferences.setMockInitialValues({
      'potv_active_profile_id': 'profile',
      'potv_user_profiles_v2': jsonEncode([
        {
          'id': 'profile',
          'preferences': {
            'audioLanguage': 'original',
            'subtitleLanguage': 'off',
            'autoplayNext': false,
          },
        },
      ]),
    });

    final preferences = await PlayerPreferences.load();
    expect(preferences.media3AudioPreference, 'any');
    expect(preferences.media3SubtitlePreference, 'disabled');
    expect(preferences.autoplayNext, isFalse);
  });
}
