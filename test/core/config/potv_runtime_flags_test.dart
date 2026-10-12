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
  test('signed 0 percent rollout disables only the selected capability', () {
    final current = PotvRuntimeFlags.initial(installationId: 'install-123');
    final update = PotvRuntimeFlags.parse(
      '{"version":1,"flags":{"sports_calendar":true},'
      '"rollout":{"sports_calendar":0}}',
      current,
    );
    expect(update, isNotNull);
    expect(update!.enabled('sports_calendar'), isFalse);
    expect(update.enabled('live_tv_catalog'), isTrue);
  });

  test('100 percent is enabled, cohorts are stable across versions', () {
    final first = PotvRuntimeFlags.parse(
      '{"version":1,"flags":{"predictive_preload":true},'
      '"rollout":{"predictive_preload":50}}',
      PotvRuntimeFlags.initial(installationId: 'install-abc'),
    )!;
    final second = PotvRuntimeFlags.parse(
      '{"version":2,"flags":{},'
      '"rollout":{"predictive_preload":50}}',
      first,
    )!;
    expect(second.enabled('predictive_preload'),
        first.enabled('predictive_preload'));

    final all = PotvRuntimeFlags.parse(
      '{"version":3,"flags":{},"rollout":{"predictive_preload":100}}',
      second,
    )!;
    expect(all.enabled('predictive_preload'), isTrue);
  });

  test('rejects invalid percentages, unfamiliar fields and missing identity', () {
    final initial = PotvRuntimeFlags.initial();
    expect(PotvRuntimeFlags.parse(
      '{"version":1,"flags":{},"rollout":{"sports_calendar":101}}',
      initial,
    ), isNull);
    expect(PotvRuntimeFlags.parse(
      '{"version":1,"flags":{},"rollout":{"sports_calendar":true}}',
      initial,
    ), isNull);
    expect(PotvRuntimeFlags.parse(
      '{"version":1,"flags":{},"rollout":{"arbitrary_key":1}}',
      initial,
    ), isNull);
    expect(PotvRuntimeFlags.parse(
      '{"version":1,"flags":{},"remote_script":"not allowed"}',
      initial,
    ), isNull);
    final limited = PotvRuntimeFlags.parse(
      '{"version":1,"flags":{},"rollout":{"live_tv_epg":50}}',
      initial,
    )!;
    expect(limited.enabled('live_tv_epg'), isFalse);
  });

}
