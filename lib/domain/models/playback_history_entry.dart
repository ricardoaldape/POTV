class PlaybackHistoryEntry {
  final String key;
  final int mediaId;
  final String mediaType;
  final String title;
  final int? season;
  final int? episode;
  final String? poster;
  final int positionMs;
  final int durationMs;
  final DateTime updatedAt;

  const PlaybackHistoryEntry({
    required this.key,
    required this.mediaId,
    required this.mediaType,
    required this.title,
    this.season,
    this.episode,
    this.poster,
    required this.positionMs,
    required this.durationMs,
    required this.updatedAt,
  });

  double get progress {
    if (durationMs <= 0) return 0;
    return (positionMs / durationMs).clamp(0, 1);
  }

  Map<String, Object?> toJson() => {
        'key': key,
        'media_id': mediaId,
        'media_type': mediaType,
        'title': title,
        'season': season,
        'episode': episode,
        'poster': poster,
        'position_ms': positionMs,
        'duration_ms': durationMs,
        'updated_at': updatedAt.toIso8601String(),
      };

  factory PlaybackHistoryEntry.fromJson(Map<String, dynamic> json) {
    return PlaybackHistoryEntry(
      key: json['key']?.toString() ?? '',
      mediaId: int.tryParse(json['media_id']?.toString() ?? '') ?? 0,
      mediaType: json['media_type']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      season: int.tryParse(json['season']?.toString() ?? ''),
      episode: int.tryParse(json['episode']?.toString() ?? ''),
      poster: json['poster']?.toString(),
      positionMs: int.tryParse(json['position_ms']?.toString() ?? '') ?? 0,
      durationMs: int.tryParse(json['duration_ms']?.toString() ?? '') ?? 0,
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
