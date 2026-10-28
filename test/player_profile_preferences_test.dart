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
  test('manual quality and audio survive failover for active profile only', () async {
    SharedPreferences.setMockInitialValues({
      'potv_active_profile_id': 'second',
      'potv_user_profiles_v2': jsonEncode([
        {'id': 'first', 'preferences': {'audioLanguage': 'original',
          'autoplayNext': false, 'customSetting': 'unchanged'}},
        {'id': 'second', 'preferences': {'audioLanguage': 'es-419',
          'autoplayNext': true, 'customSetting': 'keep-me'}},
      ]),
    });
    final updated = await PlayerPreferences.updateCurrent(
      audioLanguage: 'en',
      subtitleLanguage: 'off',
      preferredVideoHeight: 720,
      preferredAudioBitrate: 192000,
    );
    expect(updated.audioLanguage, 'en');
    expect(updated.preferredVideoHeight, 720);
    expect(updated.preferredAudioBitrate, 192000);
    expect(updated.media3AudioPreference, 'english');
    expect(updated.media3SubtitlePreference, 'disabled');

    final restored = await PlayerPreferences.load();
    expect(restored.preferredVideoHeight, 720);
    expect(restored.preferredAudioBitrate, 192000);
    expect(restored.audioLanguage, 'en');
    expect(restored.autoplayNext, true);

    final prefs = await SharedPreferences.getInstance();
    final profiles = jsonDecode(prefs.getString('potv_user_profiles_v2')!) as List;
    expect(profiles[0]['preferences']['audioLanguage'], 'original');
    expect(profiles[0]['preferences']['customSetting'], 'unchanged');
    expect(profiles[1]['preferences']['customSetting'], 'keep-me');
    expect(profiles[1]['preferences']['preferredVideoHeight'], 720);
  });

  test('without an active profile, manual override is safe and local', () async {
    SharedPreferences.setMockInitialValues({});
    final updated = await PlayerPreferences.updateCurrent(
      preferredVideoHeight: 1080,
    );
    expect(updated.preferredVideoHeight, 1080);
    expect((await PlayerPreferences.load()).preferredVideoHeight, 0);
  });

}
