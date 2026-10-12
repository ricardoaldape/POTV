import 'package:flutter_test/flutter_test.dart';
import 'package:potv/domain/models/series_episode.dart';
import 'package:potv/features/player/next_episode_selector.dart';

void main() {
  const episodes = <SeriesEpisode>[
    SeriesEpisode(season: 2, episode: 1, title: 'Season 2 Premiere'),
    SeriesEpisode(season: 1, episode: 2, title: 'Episode 2'),
    SeriesEpisode(season: 1, episode: 1, title: 'Pilot'),
  ];

  test('finds next verified episode despite unordered metadata', () {
    final next = NextEpisodeSelector.next(
      episodes,
      season: 1,
      episode: 1,
    );
    expect(next?.season, 1);
    expect(next?.episode, 2);
  });

  test('advances to next season when previous is complete', () {
    final next = NextEpisodeSelector.next(
      episodes,
      season: 1,
      episode: 2,
    );
    expect(next?.season, 2);
    expect(next?.episode, 1);
  });

  test('stops autoplay after the last catalogued episode', () {
    expect(
      NextEpisodeSelector.next(episodes, season: 2, episode: 1),
      isNull,
    );
  });

  test('never auto-opens future unreleased episodes', () {
    final future = SeriesEpisode(
      season: 2,
      episode: 2,
      title: 'Not yet released',
      releasedAt: DateTime.utc(2026, 12, 1),
    );
    final next = NextEpisodeSelector.next(
      [...episodes, future],
      season: 2,
      episode: 1,
      now: DateTime.utc(2026, 10, 12),
    );
    expect(next, isNull);
  });
}
