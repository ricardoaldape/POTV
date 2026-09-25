import 'dart:convert';

import 'package:uuid/uuid.dart';

enum SubscriptionStatus { free, pending, active, expired }

class UserAccount {
  final String id;
  final String username;
  final String? email;
  final DateTime createdAt;
  final String? telegramChatId;
  final SubscriptionStatus subscriptionStatus;
  final DateTime? subscriptionExpiresAt;

  UserAccount({
    required this.id,
    required this.username,
    this.email,
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
        'email': email,
        'createdAt': createdAt.toIso8601String(),
        'telegramChatId': telegramChatId,
        'subscriptionStatus': subscriptionStatus.index,
        'subscriptionExpiresAt': subscriptionExpiresAt?.toIso8601String(),
      };

  factory UserAccount.fromJson(Map<String, dynamic> json) {
    return UserAccount(
      id: json['id'] as String,
      username: json['username'] as String,
      email: json['email'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
      telegramChatId: json['telegramChatId'] as String?,
      subscriptionStatus:
          SubscriptionStatus.values[(json['subscriptionStatus'] as int?) ?? 0],
      subscriptionExpiresAt: json['subscriptionExpiresAt'] != null
          ? DateTime.parse(json['subscriptionExpiresAt'] as String).toUtc()
          : null,
    );
  }

  factory UserAccount.fromSupabase(Map<String, dynamic> json) {
    final statusName = json['subscription_status'] as String? ?? 'free';
    return UserAccount(
      id: json['id'] as String,
      email: json['email'] as String?,
      username: json['username'] as String? ?? json['email'] as String? ?? 'Usuario',
      createdAt: json['created_at'] == null
          ? DateTime.now().toUtc()
          : DateTime.parse(json['created_at'] as String).toUtc(),
      telegramChatId: json['telegram_chat_id']?.toString(),
      subscriptionStatus: SubscriptionStatus.values.firstWhere(
        (value) => value.name == statusName,
        orElse: () => SubscriptionStatus.free,
      ),
      subscriptionExpiresAt: json['subscription_expires_at'] == null
          ? null
          : DateTime.parse(json['subscription_expires_at'] as String).toUtc(),
    );
  }

  Map<String, dynamic> toSupabase() => {
        'id': id,
        'email': email,
        'username': username,
        'telegram_chat_id': telegramChatId,
        'subscription_status': subscriptionStatus.name,
        'subscription_expires_at': subscriptionExpiresAt?.toIso8601String(),
      };

  String toJsonString() => json.encode(toJson());

  factory UserAccount.fromJsonString(String source) =>
      UserAccount.fromJson(json.decode(source) as Map<String, dynamic>);
}
