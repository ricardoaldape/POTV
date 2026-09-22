import 'stream_candidate.dart';

class LiveChannel {
  final String id;
  final String name;
  final String? group;
  final String? epgId;
  final Uri? logo;
  final StreamCandidate stream;

  const LiveChannel({
    required this.id,
    required this.name,
    this.group,
    this.epgId,
    this.logo,
    required this.stream,
  });
}
