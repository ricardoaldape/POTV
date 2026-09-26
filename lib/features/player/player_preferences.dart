import 'package:shared_preferences/shared_preferences.dart';

enum PreferredAudioLanguage {
  spanish,
  english,
  any,
}

enum PreferredSubtitleMode {
  enabled,
  disabled,
  whenNoSpanishAudio,
}

class PlayerPreferences {
  static const _audioKey = 'player_preferred_audio_language';
  static const _subtitleKey = 'player_preferred_subtitle_mode';
  static const _autoplayKey = 'player_autoplay_enabled';

  final PreferredAudioLanguage audioLanguage;
  final PreferredSubtitleMode subtitleMode;
  final bool autoplay;

  const PlayerPreferences({
    this.audioLanguage = PreferredAudioLanguage.spanish,
    this.subtitleMode = PreferredSubtitleMode.whenNoSpanishAudio,
    this.autoplay = true,
  });

  static Future<PlayerPreferences> load() async {
    final prefs = await SharedPreferences.getInstance();

    final audioName = prefs.getString(_audioKey);
    final subtitleName = prefs.getString(_subtitleKey);

    return PlayerPreferences(
      audioLanguage: PreferredAudioLanguage.values.firstWhere(
        (value) => value.name == audioName,
        orElse: () => PreferredAudioLanguage.spanish,
      ),
      subtitleMode: PreferredSubtitleMode.values.firstWhere(
        (value) => value.name == subtitleName,
        orElse: () => PreferredSubtitleMode.whenNoSpanishAudio,
      ),
      autoplay: prefs.getBool(_autoplayKey) ?? true,
    );
  }

  static Future<void> saveAudioLanguage(
    PreferredAudioLanguage value,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_audioKey, value.name);
  }

  static Future<void> saveSubtitleMode(
    PreferredSubtitleMode value,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_subtitleKey, value.name);
  }

  static Future<void> saveAutoplay(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoplayKey, value);
  }

  String get media3AudioPreference => switch (audioLanguage) {
        PreferredAudioLanguage.spanish => 'spanish',
        PreferredAudioLanguage.english => 'english',
        PreferredAudioLanguage.any => 'any',
      };

  String get media3SubtitlePreference => switch (subtitleMode) {
        PreferredSubtitleMode.enabled => 'enabled',
        PreferredSubtitleMode.disabled => 'disabled',
        PreferredSubtitleMode.whenNoSpanishAudio => 'whenNoSpanishAudio',
      };
}
