import 'dart:convert';

import 'package:uuid/uuid.dart';

class UserProfile {
  final String id;
  final String accountId;
  final String name;
  final String avatarId;
  final bool isKids;
  final String language;

  UserProfile({
    required this.id,
    required this.accountId,
    required this.name,
    this.avatarId = 'default',
    this.isKids = false,
    this.language = 'es',
  });

  factory UserProfile.create({required String accountId, required String name}) {
    return UserProfile(id: const Uuid().v4(), accountId: accountId, name: name);
  }

  UserProfile copyWith({
    String? id,
    String? accountId,
    String? name,
    String? avatarId,
    bool? isKids,
    String? language,
  }) {
    return UserProfile(
      id: id ?? this.id,
      accountId: accountId ?? this.accountId,
      name: name ?? this.name,
      avatarId: avatarId ?? this.avatarId,
      isKids: isKids ?? this.isKids,
      language: language ?? this.language,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'accountId': accountId,
        'name': name,
        'avatarId': avatarId,
        'isKids': isKids,
        'language': language,
      };

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      accountId: json['accountId'] as String,
      name: json['name'] as String,
      avatarId: json['avatarId'] as String? ?? 'default',
      isKids: json['isKids'] as bool? ?? false,
      language: json['language'] as String? ?? 'es',
    );
  }

  String toJsonString() => json.encode(toJson());

  factory UserProfile.fromJsonString(String source) =>
      UserProfile.fromJson(json.decode(source) as Map<String, dynamic>);
}
