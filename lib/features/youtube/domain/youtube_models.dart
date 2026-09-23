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
