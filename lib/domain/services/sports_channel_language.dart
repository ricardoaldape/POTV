import '../models/live_channel.dart';
import '../models/stream_candidate.dart';

/// A viewer's preference is a ranking/filter only; it does not imply that
/// a provider actually offers audio dubbing in that language.
enum SportsLanguagePreference {
  spanish,
  english,
  all,
}

extension SportsLanguagePreferenceInfo on SportsLanguagePreference {
  String get label => switch (this) {
        SportsLanguagePreference.spanish => 'Español',
        SportsLanguagePreference.english => 'English',
        SportsLanguagePreference.all => 'Todos',
      };
}

/// Converts explicit stream language tags into consistent ES/EN labels.
/// We deliberately do not guess a stream's language from country or genre.
class SportsChannelLanguage {
  const SportsChannelLanguage();

  static const preferenceKey = 'potv_sports_language_v1';

  Set<String> tags(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const {};
    final parsed = <String>{};
    for (final value in raw.toLowerCase().split(RegExp(r'[;,|/]+'))) {
      final token = value.trim().replaceAll('_', '-');
      if (token.isEmpty) continue;
      if (RegExp(r'^(es($|-)|spa$|spanish$|espanol$|español$|latino$|latam$|castellano$)')
          .hasMatch(token)) {
        parsed.add('es');
      } else if (RegExp(r'^(en($|-)|eng$|english$|ingles$|inglés$)')
          .hasMatch(token)) {
        parsed.add('en');
      }
    }
    return parsed;
  }

  Set<String> languages(LiveChannel channel) {
    final known = <String>{};
    for (final candidate in channel.playbackCandidates) {
      known.addAll(tags(candidate.language));
    }
    return known;
  }

  bool matches(LiveChannel channel, SportsLanguagePreference preference) {
    if (preference == SportsLanguagePreference.all) return true;
    final known = languages(channel);
    if (known.isEmpty) return true; // Keep unlabelled public feeds visible.
    return known.contains(preference == SportsLanguagePreference.spanish
        ? 'es'
        : 'en');
  }

  /// A preferred language is a playback priority; all alternate servers are
  /// retained, so a failing ES feed may still fall back to another language.
  List<StreamCandidate> orderedStreams(
    LiveChannel channel,
    SportsLanguagePreference preference,
  ) {
    final all = channel.playbackCandidates;
    if (preference == SportsLanguagePreference.all || all.length <= 1) {
      return all;
    }
    final expected =
        preference == SportsLanguagePreference.spanish ? 'es' : 'en';
    final ranked = all.asMap().entries.toList(growable: false)
      ..sort((a, b) {
        int priority(StreamCandidate s) {
          final tagsForStream = tags(s.language);
          if (tagsForStream.contains(expected)) return 0;
          if (tagsForStream.isEmpty) return 1;
          return 2;
        }

        final result = priority(a.value).compareTo(priority(b.value));
        return result != 0 ? result : a.key.compareTo(b.key);
      });
    return List.unmodifiable([for (final entry in ranked) entry.value]);
  }

  List<LiveChannel> preferredChannels(
    Iterable<LiveChannel> channels,
    SportsLanguagePreference preference,
  ) {
    final visible = channels.where((c) => matches(c, preference)).toList();
    if (preference == SportsLanguagePreference.all) {
      return List.unmodifiable(visible);
    }
    final expected =
        preference == SportsLanguagePreference.spanish ? 'es' : 'en';
    final indexed = visible.asMap().entries.toList(growable: false)
      ..sort((a, b) {
        int score(LiveChannel c) {
          final lang = languages(c);
          return lang.contains(expected) ? 0 : 1;
        }

        final diff = score(a.value).compareTo(score(b.value));
        return diff != 0 ? diff : a.key.compareTo(b.key);
      });
    return List.unmodifiable([for (final item in indexed) item.value]);
  }

  String? labelFor(LiveChannel channel) {
    final known = languages(channel);
    if (known.contains('es') && known.contains('en')) return 'ES / EN';
    if (known.contains('es')) return 'ES';
    if (known.contains('en')) return 'EN';
    return null;
  }
}
