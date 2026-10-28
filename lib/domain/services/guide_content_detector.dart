import '../models/epg_program.dart';
import '../models/live_channel.dart';
import '../models/sports_event.dart';
import 'live_tv_organizer.dart';

/// An entry in POTV's unified TV and sports programme guide.
///
/// Schedule metadata describes what the source says is on air; it does not
/// certify the stream is reachable. An unlisted programme is never invented.
class DetectedGuideItem {
  final LiveChannel? channel;
  final SportsEvent? event;
  final EpgProgram? current;
  final EpgProgram? next;
  final bool isSports;

  const DetectedGuideItem({
    this.channel,
    this.event,
    this.current,
    this.next,
    required this.isSports,
  }) : assert(channel != null || event != null);

  String get id => channel?.id ?? 'event:${event!.id}';
  String get channelName => channel?.name ?? event!.competition;
  String? get currentTitle => event?.title ?? current?.title;
  String? get nextTitle => next?.title;
  bool get hasConfirmedProgramme => event != null || current != null;
  DateTime? get startsAt => event?.startsAt ?? current?.startsAt;
  DateTime? get endsAt => current?.endsAt;
}

/// Source-agnostic detection: XMLTV/partner EPG matched by channel id or an
/// unambiguous display name; sports events only when the partner attached
/// an actual stream to the exact event.
class GuideContentDetector {
  const GuideContentDetector();

  List<DetectedGuideItem> build({
    required Iterable<LiveChannel> channels,
    required Iterable<EpgProgram> programs,
    required Iterable<SportsEvent> events,
    required DateTime now,
  }) {
    final guide = LiveTvGuide(programs);
    final organizer = const LiveTvOrganizer();
    final items = <DetectedGuideItem>[];
    final seenChannels = <String>{};
    for (final channel in channels) {
      if (!organizer.isAllowedChannel(channel) ||
          !seenChannels.add(channel.id) ||
          channel.playbackCandidates.isEmpty) {
        continue;
      }
      items.add(DetectedGuideItem(
        channel: channel,
        current: guide.onAir(channel, now),
        next: guide.upNext(channel, now),
        isSports: organizer.categoryFor(channel) == LiveTvCategory.sports,
      ));
    }

    final seenEvents = <String>{};
    for (final event in events) {
      if (!event.isLive ||
          event.streams.isEmpty ||
          !seenEvents.add(event.id)) {
        continue;
      }
      items.add(DetectedGuideItem(event: event, isSports: true));
    }

    // Programme-bearing entries first; a silent EPG never implies a blank
    // channel or a particular match. Preserve channel discovery afterwards.
    items.sort((a, b) {
      final rankA = a.hasConfirmedProgramme ? 0 : (a.next != null ? 1 : 2);
      final rankB = b.hasConfirmedProgramme ? 0 : (b.next != null ? 1 : 2);
      if (rankA != rankB) return rankA.compareTo(rankB);
      return a.channelName.toLowerCase().compareTo(b.channelName.toLowerCase());
    });
    return List.unmodifiable(items);
  }

  List<DetectedGuideItem> filter(
    Iterable<DetectedGuideItem> items, {
    String search = '',
    bool? sports,
    bool withProgrammeOnly = false,
  }) {
    final query = LiveTvOrganizer.normalize(search);
    return items.where((item) {
      if (sports != null && item.isSports != sports) return false;
      if (withProgrammeOnly && !item.hasConfirmedProgramme && item.next == null) {
        return false;
      }
      if (query.isEmpty) return true;
      final text = LiveTvOrganizer.normalize([
        item.channelName,
        item.currentTitle ?? '',
        item.nextTitle ?? '',
        item.channel?.group ?? '',
      ].join(' '));
      return text.contains(query);
    }).toList(growable: false);
  }
}
