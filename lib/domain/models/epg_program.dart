class EpgProgram {
  final String channelId;
  /// XMLTV channel display names used for exact, unambiguous guide matching.
  final List<String> channelNames;
  final String title;
  final String? description;
  final DateTime startsAt;
  final DateTime endsAt;

  const EpgProgram({
    required this.channelId,
    this.channelNames = const [],
    required this.title,
    this.description,
    required this.startsAt,
    required this.endsAt,
  });

  bool isOnAir(DateTime now) =>
      !now.isBefore(startsAt) && now.isBefore(endsAt);
}
