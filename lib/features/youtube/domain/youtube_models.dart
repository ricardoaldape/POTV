class PotvYoutubeVideo {
  final String id;
  final String title;
  final String author;
  final String channelId;
  final String thumbnailUrl;
  final Duration? duration;
  final DateTime? uploadDate;
  final int viewCount;
  final bool isLive;
  final String description;

  const PotvYoutubeVideo({
    required this.id,
    required this.title,
    required this.author,
    required this.channelId,
    required this.thumbnailUrl,
    this.duration,
    this.uploadDate,
    this.viewCount = 0,
    this.isLive = false,
    this.description = '',
  });

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'author': author,
        'channel_id': channelId,
        'thumbnail_url': thumbnailUrl,
        'duration_ms': duration?.inMilliseconds,
        'upload_date': uploadDate?.toIso8601String(),
        'view_count': viewCount,
        'is_live': isLive,
        'description': description,
      };

  factory PotvYoutubeVideo.fromJson(Map<String, dynamic> json) {
    final durationMs = int.tryParse(json['duration_ms']?.toString() ?? '');
    final uploadDate = DateTime.tryParse(json['upload_date']?.toString() ?? '');
    return PotvYoutubeVideo(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      author: json['author']?.toString() ?? '',
      channelId: json['channel_id']?.toString() ?? '',
      thumbnailUrl: json['thumbnail_url']?.toString() ?? '',
      duration: durationMs == null ? null : Duration(milliseconds: durationMs),
      uploadDate: uploadDate,
      viewCount: int.tryParse(json['view_count']?.toString() ?? '') ?? 0,
      isLive: json['is_live'] == true,
      description: json['description']?.toString() ?? '',
    );
  }
}

class PotvYoutubeChannel {
  final String id;
  final String title;
  final String logoUrl;
  final String bannerUrl;
  final int? subscribersCount;

  const PotvYoutubeChannel({
    required this.id,
    required this.title,
    required this.logoUrl,
    required this.bannerUrl,
    this.subscribersCount,
  });
}

class PotvYoutubeSubscription {
  final String channelId;
  final String title;
  final String? logoUrl;

  const PotvYoutubeSubscription({
    required this.channelId,
    required this.title,
    this.logoUrl,
  });

  Map<String, Object?> toJson() => {
        'channel_id': channelId,
        'title': title,
        'logo_url': logoUrl,
      };

  factory PotvYoutubeSubscription.fromJson(Map<String, dynamic> json) {
    return PotvYoutubeSubscription(
      channelId: json['channel_id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      logoUrl: json['logo_url']?.toString(),
    );
  }
}
