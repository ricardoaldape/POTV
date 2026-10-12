import 'package:flutter_test/flutter_test.dart';
import 'package:potv/core/config/potv_runtime_flags.dart';

void main() {
  test('new functionality stays disabled by default', () {
    final flags = PotvRuntimeFlags.initial();
    expect(flags.enabled('predictive_preload'), isTrue);
    expect(flags.enabled('sports_event_matching'), isTrue);
    expect(flags.enabled('missing_capability'), isFalse);
  });

  test('validated update changes only named switches', () {
    final updated = PotvRuntimeFlags.parse(
      '{"version":1,"flags":{"live_tv_epg":false}}',
      PotvRuntimeFlags.initial(),
    );
    expect(updated, isNotNull);
    expect(updated!.enabled('live_tv_epg'), isFalse);
    expect(updated.enabled('live_tv_catalog'), isTrue);
  });

  test('rejects stale, invalid and unknown remote configuration', () {
    final current = PotvRuntimeFlags.parse(
      '{"version":3,"flags":{"sports_calendar":false}}',
      PotvRuntimeFlags.initial(),
    )!;
    expect(PotvRuntimeFlags.parse('{"version":2,"flags":{}}', current), isNull);
    expect(PotvRuntimeFlags.parse(
      '{"version":4,"flags":{"unrecognized":true}}', current), isNull);
    expect(PotvRuntimeFlags.parse(
      '{"version":4,"flags":{"live_tv_epg":"false"}}', current), isNull);
    expect(PotvRuntimeFlags.parse('not-json', current), isNull);
    expect(current.enabled('sports_calendar'), isFalse);
  });
}
