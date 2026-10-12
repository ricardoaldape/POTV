import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';

/// Injected at boot after reading the last known valid local configuration.
final potvRuntimeFlagStoreProvider = ChangeNotifierProvider<PotvRuntimeFlagStore>((ref) {
  throw StateError('Runtime flag store must be initialized before runApp');
});

/// Runtime switches for components that may fail independently.
///
/// Only named boolean capabilities are configurable. Remote JSON never becomes
/// executable code, and cannot inject URLs, credentials or stream sources.
class PotvRuntimeFlags {
  PotvRuntimeFlags._(
    this.version,
    this.updatedAt,
    this.values,
    this.rolloutPercent,
    this.installationId,
  );

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
    'predictive_preload': true,
    'youtube_integration': false,
    'external_source_resolution': true,
  };

  final int version;
  final DateTime updatedAt;
  final Map<String, bool> values;
  final Map<String, int> rolloutPercent;
  final String installationId;

  /// A false flag always disables the capability globally. Optional rollout
  /// percentages can only restrict enabled features to a stable install cohort.
  bool enabled(String key) {
    if (!(values[key] ?? defaults[key] ?? false)) return false;
    final percentage = rolloutPercent[key] ?? 100;
    if (percentage >= 100) return true;
    if (percentage <= 0 || installationId.isEmpty) return false;
    final digest = sha256.convert(
      utf8.encode('$installationId:$key'),
    ).bytes;
    final bucket = ((digest[0] << 24) |
            (digest[1] << 16) |
            (digest[2] << 8) |
            digest[3]) %
        100;
    return bucket < percentage;
  }

  static PotvRuntimeFlags initial({String installationId = ''}) =>
      PotvRuntimeFlags._(
        0,
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        Map.unmodifiable(defaults),
        const <String, int>{},
        installationId,
      );

  /// Strict parser: malformed manifests do not replace the last known good.
  ///
  /// Expected structure: {"version":1,"flags":{"predictive_preload":false}}
  /// Version must rise to prevent accidental rollback to stale configurations.
  static PotvRuntimeFlags? parse(String raw, PotvRuntimeFlags current) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded.keys.any((key) =>
          key != 'version' && key != 'flags' && key != 'rollout')) {
        return null;
      }
      final rollout = decoded['rollout'] ?? <String, dynamic>{};
      if (rollout is! Map<String, dynamic>) return null;
      if (rollout.entries.any((entry) =>
          !supported.contains(entry.key) ||
          entry.value is! int ||
          (entry.value as int) < 0 ||
          (entry.value as int) > 100)) {
        return null;
      }
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
        Map.unmodifiable(rollout.cast<String, int>()),
        current.installationId,
      );
    } catch (_) {
      return null;
    }
  }

  String toJson() => jsonEncode({
        'version': version,
        'flags': values,
        'rollout': rolloutPercent,
      });
}

/// Resilience cache with atomic-like validation-before-replace behavior.
///
/// The caller supplies a trusted HTTPS manifest fetcher, verifies its origin
/// and authenticity, and invokes refresh. Never consume an unsigned manifest
/// from an untrusted endpoint. A production deployment must authenticate the
/// control plane before enabling remote updates.
class PotvRuntimeFlagStore extends ChangeNotifier {
  PotvRuntimeFlagStore(this.preferences)
      : _current = PotvRuntimeFlags.initial(
          installationId: preferences.getString('potv_device_id') ?? '',
        );

  final SharedPreferences preferences;
  PotvRuntimeFlags _current;

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
