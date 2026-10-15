import 'dart:convert';

import 'package:uuid/uuid.dart';

class ProfilePreferences {
  final String audioLanguage;
  final String subtitleLanguage;
  final bool autoplayNext;
  final String sportsLanguage;

  const ProfilePreferences({
    this.audioLanguage = 'es-419',
    this.subtitleLanguage = 'es',
    this.autoplayNext = true,
    this.sportsLanguage = 'es',
  });

  ProfilePreferences copyWith({
    String? audioLanguage,
    String? subtitleLanguage,
    bool? autoplayNext,
    String? sportsLanguage,
  }) =>
      ProfilePreferences(
        audioLanguage: audioLanguage ?? this.audioLanguage,
        subtitleLanguage: subtitleLanguage ?? this.subtitleLanguage,
        autoplayNext: autoplayNext ?? this.autoplayNext,
        sportsLanguage: sportsLanguage ?? this.sportsLanguage,
      );

  Map<String, dynamic> toJson() => {
        'audioLanguage': audioLanguage,
        'subtitleLanguage': subtitleLanguage,
        'autoplayNext': autoplayNext,
        'sportsLanguage': sportsLanguage,
      };

  factory ProfilePreferences.fromJson(Map<String, dynamic>? json) =>
      ProfilePreferences(
        audioLanguage: json?['audioLanguage']?.toString() ?? 'es-419',
        subtitleLanguage: json?['subtitleLanguage']?.toString() ?? 'es',
        autoplayNext: json?['autoplayNext'] as bool? ?? true,
        sportsLanguage: json?['sportsLanguage']?.toString() ?? 'es',
      );
}

class UserProfile {
  final String id;
  final String accountId;
  final String name;
  final String avatarId;
  final bool isKids;
  final String language;
  final ProfilePreferences preferences;

  const UserProfile({
    required this.id,
    required this.accountId,
    required this.name,
    this.avatarId = 'ocean',
    this.isKids = false,
    this.language = 'es-MX',
    this.preferences = const ProfilePreferences(),
  });

  factory UserProfile.create({
    required String accountId,
    required String name,
    String avatarId = 'ocean',
    bool isKids = false,
  }) =>
      UserProfile(
        id: const Uuid().v4(),
        accountId: accountId,
        name: name,
        avatarId: avatarId,
        isKids: isKids,
      );

  UserProfile copyWith({
    String? id,
    String? accountId,
    String? name,
    String? avatarId,
    bool? isKids,
    String? language,
    ProfilePreferences? preferences,
  }) =>
      UserProfile(
        id: id ?? this.id,
        accountId: accountId ?? this.accountId,
        name: name ?? this.name,
        avatarId: avatarId ?? this.avatarId,
        isKids: isKids ?? this.isKids,
        language: language ?? this.language,
        preferences: preferences ?? this.preferences,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'accountId': accountId,
        'name': name,
        'avatarId': avatarId,
        'isKids': isKids,
        'language': language,
        'preferences': preferences.toJson(),
      };

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        id: json['id']?.toString() ?? '',
        accountId: json['accountId']?.toString() ?? '',
        name: json['name']?.toString() ?? 'Perfil',
        avatarId: json['avatarId']?.toString() ?? 'ocean',
        isKids: json['isKids'] as bool? ?? false,
        language: json['language']?.toString() ?? 'es-MX',
        preferences: ProfilePreferences.fromJson(
          json['preferences'] is Map<String, dynamic>
              ? json['preferences'] as Map<String, dynamic>
              : null,
        ),
      );

  String toJsonString() => json.encode(toJson());
}
