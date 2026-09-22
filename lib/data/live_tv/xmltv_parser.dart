import 'package:collection/collection.dart';
import 'package:xml/xml.dart';

import '../../domain/models/epg_program.dart';

class XmlTvParser {
  static List<EpgProgram> parse(String raw) {
    final document = XmlDocument.parse(raw);
    final programs = <EpgProgram>[];

    for (final node in document.findAllElements('programme')) {
      final channel = node.getAttribute('channel');
      final start = _parseDate(node.getAttribute('start'));
      final stop = _parseDate(node.getAttribute('stop'));
      final title = node.findElements('title').firstOrNull?.innerText.trim();

      if (channel == null ||
          start == null ||
          stop == null ||
          title == null ||
          title.isEmpty) {
        continue;
      }

      programs.add(
        EpgProgram(
          channelId: channel,
          title: title,
          description: node.findElements('desc').firstOrNull?.innerText.trim(),
          startsAt: start,
          endsAt: stop,
        ),
      );
    }
    return programs;
  }

  static DateTime? _parseDate(String? raw) {
    if (raw == null || raw.length < 14) return null;
    final digits = raw.substring(0, 14);
    final values = [
      int.tryParse(digits.substring(0, 4)),
      int.tryParse(digits.substring(4, 6)),
      int.tryParse(digits.substring(6, 8)),
      int.tryParse(digits.substring(8, 10)),
      int.tryParse(digits.substring(10, 12)),
      int.tryParse(digits.substring(12, 14)),
    ];
    if (values.contains(null)) return null;

    var value = DateTime.utc(
      values[0]!, values[1]!, values[2]!,
      values[3]!, values[4]!, values[5]!,
    );

    final timezone = raw.length >= 20 ? raw.substring(15).trim() : '';
    final match = RegExp(r'^([+-])(\d{2})(\d{2})').firstMatch(timezone);
    if (match != null) {
      final offset = Duration(
        hours: int.parse(match.group(2)!),
        minutes: int.parse(match.group(3)!),
      );
      value = match.group(1) == '+' ? value.subtract(offset) : value.add(offset);
    }
    return value.toLocal();
  }
}
