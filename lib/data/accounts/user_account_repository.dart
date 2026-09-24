import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'user_account.dart';
import 'user_profile.dart';

class UserAccountRepository {
  static const _kAccountKey = 'potv_user_account';
  static const _kProfilesKey = 'potv_user_profiles';
  static const _kActiveProfileKey = 'potv_active_profile_id';

  final SharedPreferences _prefs;

  UserAccountRepository._(this._prefs);

  static Future<UserAccountRepository> getInstance() async {
    final prefs = await SharedPreferences.getInstance();
    return UserAccountRepository._(prefs);
  }

  Future<void> saveAccount(UserAccount account) async {
    await _prefs.setString(_kAccountKey, account.toJsonString());
  }

  UserAccount? loadAccount() {
    final s = _prefs.getString(_kAccountKey);
    if (s == null) return null;
    try {
      return UserAccount.fromJsonString(s);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveProfiles(List<UserProfile> profiles) async {
    final list = profiles.map((p) => p.toJson()).toList();
    await _prefs.setString(_kProfilesKey, json.encode(list));
  }

  List<UserProfile> loadProfiles() {
    final s = _prefs.getString(_kProfilesKey);
    if (s == null) return <UserProfile>[];
    try {
      final list = json.decode(s) as List<dynamic>;
      return list.map((e) => UserProfile.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return <UserProfile>[];
    }
  }

  Future<void> saveActiveProfileId(String? id) async {
    if (id == null) {
      await _prefs.remove(_kActiveProfileKey);
    } else {
      await _prefs.setString(_kActiveProfileKey, id);
    }
  }

  String? loadActiveProfileId() {
    return _prefs.getString(_kActiveProfileKey);
  }

  Future<void> clearAll() async {
    await _prefs.remove(_kAccountKey);
    await _prefs.remove(_kProfilesKey);
    await _prefs.remove(_kActiveProfileKey);
  }
}
