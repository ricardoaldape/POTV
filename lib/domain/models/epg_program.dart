class EpgProgram {
  final String channelId;
  final String title;
  final String? description;
  final DateTime startsAt;
  final DateTime endsAt;

  const EpgProgram({
    required this.channelId,
    required this.title,
    this.description,
    required this.startsAt,
    required this.endsAt,
  });

  bool isOnAir(DateTime now) =>
      !now.isBefore(startsAt) && now.isBefore(endsAt);
}
