class SeriesEpisode {
  final int season;
  final int episode;
  final String title;
  final String? overview;
  final Uri? thumbnail;
  final DateTime? releasedAt;

  const SeriesEpisode({
    required this.season,
    required this.episode,
    required this.title,
    this.overview,
    this.thumbnail,
    this.releasedAt,
  });

  String get code => 'T$season E$episode';
}
