/// Circuit breaker protecting POTV against repeatedly failing source providers.
///
/// An unavailable provider is skipped temporarily, while other providers keep
/// working. After the cooldown a single half-open request checks recovery.
enum ProviderCircuitState { closed, open, halfOpen }

class ProviderHealthSnapshot {
  const ProviderHealthSnapshot({
    required this.state,
    required this.successes,
    required this.failures,
    required this.consecutiveFailures,
    this.retryAt,
  });

  final ProviderCircuitState state;
  final int successes;
  final int failures;
  final int consecutiveFailures;
  final DateTime? retryAt;

  /// 0.0 to 1.0, intended for diagnostics rather than user-facing claims.
  double get successRate {
    final total = successes + failures;
    return total == 0 ? 1.0 : successes / total;
  }
}

class ProviderCircuitBreaker {
  ProviderCircuitBreaker({
    this.failureThreshold = 3,
    this.cooldown = const Duration(minutes: 1),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    if (failureThreshold < 1 || cooldown <= Duration.zero) {
      throw ArgumentError('Invalid circuit-breaker thresholds');
    }
  }

  final int failureThreshold;
  final Duration cooldown;
  final DateTime Function() _clock;
  final Map<String, _Circuit> _circuits = {};

  /// Reserve permission to call the provider. During half-open, at most one
  /// probe can be in flight, even across separate media items.
  bool canAttempt(String providerId) {
    final circuit = _circuits.putIfAbsent(providerId, _Circuit.new);
    final retryAt = circuit.retryAt;
    if (retryAt == null) return true;
    if (_clock().isBefore(retryAt)) return false;
    if (circuit.probeInProgress) return false;
    circuit.probeInProgress = true;
    return true;
  }

  void recordSuccess(String providerId) {
    final circuit = _circuits.putIfAbsent(providerId, _Circuit.new);
    circuit.successes++;
    circuit.consecutiveFailures = 0;
    circuit.retryAt = null;
    circuit.probeInProgress = false;
  }

  void recordFailure(String providerId) {
    final circuit = _circuits.putIfAbsent(providerId, _Circuit.new);
    circuit.failures++;
    circuit.consecutiveFailures++;
    if (circuit.probeInProgress ||
        circuit.consecutiveFailures >= failureThreshold) {
      circuit.retryAt = _clock().add(cooldown);
    }
    circuit.probeInProgress = false;
  }

  ProviderHealthSnapshot snapshot(String providerId) {
    final circuit = _circuits[providerId];
    if (circuit == null) {
      return const ProviderHealthSnapshot(
        state: ProviderCircuitState.closed,
        successes: 0,
        failures: 0,
        consecutiveFailures: 0,
      );
    }
    final retryAt = circuit.retryAt;
    final state = retryAt == null
        ? ProviderCircuitState.closed
        : _clock().isBefore(retryAt)
            ? ProviderCircuitState.open
            : ProviderCircuitState.halfOpen;
    return ProviderHealthSnapshot(
      state: state,
      successes: circuit.successes,
      failures: circuit.failures,
      consecutiveFailures: circuit.consecutiveFailures,
      retryAt: retryAt,
    );
  }

  void reset(String providerId) => _circuits.remove(providerId);
}

class _Circuit {
  int successes = 0;
  int failures = 0;
  int consecutiveFailures = 0;
  DateTime? retryAt;
  bool probeInProgress = false;
}
