import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Injected at boot after reading the last known valid local configuration.
final potvRuntimeFlagStoreProvider = ChangeNotifierProvider<PotvRuntimeFlagStore>((ref) {
  throw StateError('Runtime flag store must be initialized before runApp');
});

/// Runtime switches for components that may fail independently.
///
/// Only named boolean capabilities are configurable. Remote JSON never becomes
/// executable code, and cannot inject URLs, credentials or stream sources.
class PotvRuntimeFlags {
  PotvRuntimeFlags._(this.version, this.updatedAt, this.values);

  static const storageKey = 'potv.runtime_flags.v1';
  static const supported = <String>{
    'sports_calendar',
    'sports_event_matching',
    'live_tv_catalog',
    'live_tv_epg',
    'predictive_preload',
    'youtube_integration',
    'external_source_resolution',
  };

  // Existing experiences remain enabled by default. New risky functionality
  // stays opt-in until integration tests and rollout have passed.
  static const defaults = <String, bool>{
    'sports_calendar': true,
    'sports_event_matching': true,
    'live_tv_catalog': true,
    'live_tv_epg': true,
    'predictive_preload': false,
    'youtube_integration': false,
    'external_source_resolution': true,
  };

  final int version;
  final DateTime updatedAt;
  final Map<String, bool> values;

  bool enabled(String key) => values[key] ?? defaults[key] ?? false;

  static PotvRuntimeFlags initial() =>
      PotvRuntimeFlags._(0, DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
          Map.unmodifiable(defaults));

  /// Strict parser: malformed manifests do not replace the last known good.
  ///
  /// Expected structure: {"version":1,"flags":{"predictive_preload":false}}
  /// Version must rise to prevent accidental rollback to stale configurations.
  static PotvRuntimeFlags? parse(String raw, PotvRuntimeFlags current) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final version = decoded['version'];
      final rawFlags = decoded['flags'];
      if (version is! int || version <= current.version ||
          rawFlags is! Map<String, dynamic>) {
        return null;
      }
      if (rawFlags.keys.any((key) => !supported.contains(key))) return null;
      if (rawFlags.values.any((value) => value is! bool)) return null;
      final merged = Map<String, bool>.from(current.values);
      rawFlags.forEach((key, value) => merged[key] = value as bool);
      return PotvRuntimeFlags._(
        version,
        DateTime.now().toUtc(),
        Map.unmodifiable(merged),
      );
    } catch (_) {
      return null;
    }
  }

  String toJson() => jsonEncode({'version': version, 'flags': values});
}

/// Resilience cache with atomic-like validation-before-replace behavior.
///
/// The caller supplies a trusted HTTPS manifest fetcher, verifies its origin
/// and authenticity, and invokes refresh. Never consume an unsigned manifest
/// from an untrusted endpoint. A production deployment must authenticate the
/// control plane before enabling remote updates.
class PotvRuntimeFlagStore extends ChangeNotifier {
  PotvRuntimeFlagStore(this.preferences);

  final SharedPreferences preferences;
  PotvRuntimeFlags _current = PotvRuntimeFlags.initial();

  PotvRuntimeFlags get current => _current;

  void load() {
    final cached = preferences.getString(PotvRuntimeFlags.storageKey);
    if (cached == null) return;
    final parsed = PotvRuntimeFlags.parse(cached, _current);
    if (parsed != null) _current = parsed;
  }

  /// Only call with an authenticated manifest from the trusted control plane.
  Future<bool> applyVerifiedManifest(String json) async {
    final next = PotvRuntimeFlags.parse(json, _current);
    if (next == null) return false;
    final persisted = await preferences.setString(
      PotvRuntimeFlags.storageKey, next.toJson());
    if (!persisted) return false;
    _current = next;
    notifyListeners();
    return true;
  }
}
