import 'package:flutter_test/flutter_test.dart';
import 'package:potv/data/live_tv/xmltv_parser.dart';

void main() {
  test('parses XMLTV programme metadata', () {
    const raw = '''<tv>
      <programme start="20260921200000 +0000" stop="20260921210000 +0000" channel="demo">
        <title>Programa Demo</title>
        <desc>Descripción</desc>
      </programme>
    </tv>''';

    final programs = XmlTvParser.parse(raw);

    expect(programs, hasLength(1));
    expect(programs.first.channelId, 'demo');
    expect(programs.first.title, 'Programa Demo');
  });
}
