import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:potv/data/resolution/provider_circuit_breaker.dart';

void main() {
  test('opens after repeated failures, retries exactly once and recovers',
      () async {
    var now = DateTime.utc(2026, 10, 12, 10);
    final health = ProviderCircuitBreaker(
      failureThreshold: 3,
      cooldown: const Duration(seconds: 30),
      clock: () => now,
    );

    for (var i = 0; i < 3; i++) {
      expect(health.canAttempt('source'), isTrue);
      health.recordFailure('source');
    }
    expect(health.snapshot('source').state, ProviderCircuitState.open);
    expect(health.canAttempt('source'), isFalse);

    now = now.add(const Duration(seconds: 31));
    expect(health.snapshot('source').state, ProviderCircuitState.halfOpen);
    expect(health.canAttempt('source'), isTrue);
    expect(health.canAttempt('source'), isFalse);

    health.recordSuccess('source');
    expect(health.snapshot('source').state, ProviderCircuitState.closed);
    expect(health.snapshot('source').successRate, closeTo(0.25, 0.001));
    expect(health.canAttempt('source'), isTrue);
  });

  test('failed half-open probe immediately reopens until next cooldown', () {
    var now = DateTime.utc(2026, 10, 12, 10);
    final health = ProviderCircuitBreaker(
      failureThreshold: 2,
      cooldown: const Duration(seconds: 10),
      clock: () => now,
    );
    for (var i = 0; i < 2; i++) {
      expect(health.canAttempt('a'), isTrue);
      health.recordFailure('a');
    }
    now = now.add(const Duration(seconds: 11));
    expect(health.canAttempt('a'), isTrue);
    health.recordFailure('a');
    expect(health.snapshot('a').state, ProviderCircuitState.open);
    expect(health.canAttempt('a'), isFalse);
    expect(health.canAttempt('b'), isTrue);
  });

  test('one failed provider cannot impact another provider', () {
    final health = ProviderCircuitBreaker(failureThreshold: 1);
    expect(health.canAttempt('broken'), isTrue);
    health.recordFailure('broken');
    expect(health.canAttempt('broken'), isFalse);
    expect(health.canAttempt('working'), isTrue);
    health.recordSuccess('working');
    expect(health.snapshot('working').successes, 1);
  });
}
