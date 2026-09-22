enum MediaType { movie, tv }

class MediaItem {
  final int id;
  final MediaType type;
  final String title;
  final String? overview;
  final String? year;
  final Uri? poster;
  final Uri? backdrop;

  const MediaItem({
    required this.id,
    required this.type,
    required this.title,
    this.overview,
    this.year,
    this.poster,
    this.backdrop,
  });

  String get mediaTypeName => switch (type) {
        MediaType.movie => 'movie',
        MediaType.tv => 'tv',
      };
}
