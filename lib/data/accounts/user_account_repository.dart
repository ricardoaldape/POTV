import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'user_account.dart';
import 'user_profile.dart';

class UserAccountRepository {
  static const _kAccountKey = 'potv_user_account';
  static const _kProfilesKey = 'potv_user_profiles_v2';
  static const _kLegacyProfilesKey = 'potv_user_profiles';
  static const _kActiveProfileKey = 'potv_active_profile_id';

  final SharedPreferences _prefs;
  UserAccountRepository._(this._prefs);

  static Future<UserAccountRepository> getInstance() async =>
      UserAccountRepository._(await SharedPreferences.getInstance());

  Future<void> saveAccount(UserAccount account) =>
      _prefs.setString(_kAccountKey, account.toJsonString());

  UserAccount? loadAccount() {
    final raw = _prefs.getString(_kAccountKey);
    if (raw == null) return null;
    try {
      return UserAccount.fromJsonString(raw);
    } catch (_) {
      return null;
    }
  }

  List<UserProfile> _allProfiles() {
    final raw = _prefs.getString(_kProfilesKey) ?? _prefs.getString(_kLegacyProfilesKey);
    if (raw == null) return const [];
    try {
      final decoded = json.decode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((value) => UserProfile.fromJson(Map<String, dynamic>.from(value)))
          .where((profile) => profile.id.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  List<UserProfile> loadProfiles(String accountId) =>
      _allProfiles().where((p) => p.accountId == accountId).toList(growable: false);

  Future<void> saveProfiles(String accountId, List<UserProfile> profiles) async {
    final retained = _allProfiles().where((p) => p.accountId != accountId);
    final merged = [...retained, ...profiles];
    await _prefs.setString(
      _kProfilesKey,
      json.encode([for (final p in merged) p.toJson()]),
    );
    await _prefs.remove(_kLegacyProfilesKey);
  }

  Future<void> saveActiveProfileId(String? id) async {
    if (id == null) {
      await _prefs.remove(_kActiveProfileKey);
    } else {
      await _prefs.setString(_kActiveProfileKey, id);
    }
  }

  String? loadActiveProfileId() => _prefs.getString(_kActiveProfileKey);

  Future<void> clearSession() async {
    await _prefs.remove(_kAccountKey);
    await _prefs.remove(_kActiveProfileKey);
  }
}
