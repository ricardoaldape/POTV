import 'dart:convert';

import 'package:uuid/uuid.dart';

enum SubscriptionStatus { free, pending, active, expired }

class UserAccount {
  final String id;
  final String username;
  final DateTime createdAt;
  final String? telegramChatId;
  final SubscriptionStatus subscriptionStatus;
  final DateTime? subscriptionExpiresAt;

  UserAccount({
    required this.id,
    required this.username,
    required this.createdAt,
    this.telegramChatId,
    this.subscriptionStatus = SubscriptionStatus.free,
    this.subscriptionExpiresAt,
  });

  factory UserAccount.create(String username) {
    return UserAccount(
      id: const Uuid().v4(),
      username: username,
      createdAt: DateTime.now().toUtc(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'createdAt': createdAt.toIso8601String(),
        'telegramChatId': telegramChatId,
        'subscriptionStatus': subscriptionStatus.index,
        'subscriptionExpiresAt': subscriptionExpiresAt?.toIso8601String(),
      };

  factory UserAccount.fromJson(Map<String, dynamic> json) {
    return UserAccount(
      id: json['id'] as String,
      username: json['username'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
      telegramChatId: json['telegramChatId'] as String?,
      subscriptionStatus:
          SubscriptionStatus.values[(json['subscriptionStatus'] as int?) ?? 0],
      subscriptionExpiresAt: json['subscriptionExpiresAt'] != null
          ? DateTime.parse(json['subscriptionExpiresAt'] as String).toUtc()
          : null,
    );
  }

  String toJsonString() => json.encode(toJson());

  factory UserAccount.fromJsonString(String source) =>
      UserAccount.fromJson(json.decode(source) as Map<String, dynamic>);
}
