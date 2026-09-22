enum MediaType { movie, tv, anime }

class MediaItem {
  final int id;
  final MediaType type;
  final String title;
  final String? overview;
  final String? year;
  final Uri? poster;
  final Uri? backdrop;
  final String? externalId;

  const MediaItem({
    required this.id,
    required this.type,
    required this.title,
    this.overview,
    this.year,
    this.poster,
    this.backdrop,
    this.externalId,
  });

  String get mediaTypeName => switch (type) {
        MediaType.movie => 'movie',
        MediaType.tv => 'tv',
        MediaType.anime => 'anime',
      };

  String get typeLabel => switch (type) {
        MediaType.movie => 'Película',
        MediaType.tv => 'Serie',
        MediaType.anime => 'Anime',
      };
}
