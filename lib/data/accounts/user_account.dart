import 'dart:convert';

enum SubscriptionStatus { free, pending, active, expired }

class UserAccount {
  final String id;
  final String email;
  final String username;
  final DateTime createdAt;
  final String? telegramChatId;
  final SubscriptionStatus subscriptionStatus;
  final DateTime? subscriptionExpiresAt;

  const UserAccount({
    required this.id,
    required this.email,
    required this.username,
    required this.createdAt,
    this.telegramChatId,
    this.subscriptionStatus = SubscriptionStatus.free,
    this.subscriptionExpiresAt,
  });

  UserAccount copyWith({
    String? id,
    String? email,
    String? username,
    DateTime? createdAt,
    String? telegramChatId,
    bool clearTelegramChatId = false,
    SubscriptionStatus? subscriptionStatus,
    DateTime? subscriptionExpiresAt,
    bool clearSubscriptionExpiresAt = false,
  }) {
    return UserAccount(
      id: id ?? this.id,
      email: email ?? this.email,
      username: username ?? this.username,
      createdAt: createdAt ?? this.createdAt,
      telegramChatId:
          clearTelegramChatId ? null : (telegramChatId ?? this.telegramChatId),
      subscriptionStatus: subscriptionStatus ?? this.subscriptionStatus,
      subscriptionExpiresAt: clearSubscriptionExpiresAt
          ? null
          : (subscriptionExpiresAt ?? this.subscriptionExpiresAt),
    );
  }

  static SubscriptionStatus _status(Object? value) {
    final raw = value?.toString().toLowerCase().trim();
    return SubscriptionStatus.values.firstWhere(
      (item) => item.name == raw,
      orElse: () => SubscriptionStatus.free,
    );
  }

  factory UserAccount.fromApi(Map<String, dynamic> json) {
    return UserAccount(
      id: json['id']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      username: json['username']?.toString() ??
          json['email']?.toString().split('@').first ??
          'POTV',
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '')?.toUtc() ??
          DateTime.now().toUtc(),
      telegramChatId: json['telegram_chat_id']?.toString(),
      subscriptionStatus: _status(json['subscription_status'] ?? json['status']),
      subscriptionExpiresAt: DateTime.tryParse(
        (json['subscription_expires_at'] ?? json['expires_at'])?.toString() ?? '',
      )?.toUtc(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'username': username,
        'createdAt': createdAt.toIso8601String(),
        'telegramChatId': telegramChatId,
        'subscriptionStatus': subscriptionStatus.name,
        'subscriptionExpiresAt': subscriptionExpiresAt?.toIso8601String(),
      };

  factory UserAccount.fromJson(Map<String, dynamic> json) {
    final rawStatus = json['subscriptionStatus'];
    SubscriptionStatus status;
    if (rawStatus is int && rawStatus >= 0 && rawStatus < SubscriptionStatus.values.length) {
      status = SubscriptionStatus.values[rawStatus];
    } else {
      status = _status(rawStatus);
    }
    return UserAccount(
      id: json['id']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '')?.toUtc() ??
          DateTime.now().toUtc(),
      telegramChatId: json['telegramChatId']?.toString(),
      subscriptionStatus: status,
      subscriptionExpiresAt:
          DateTime.tryParse(json['subscriptionExpiresAt']?.toString() ?? '')?.toUtc(),
    );
  }

  String toJsonString() => json.encode(toJson());

  factory UserAccount.fromJsonString(String source) =>
      UserAccount.fromJson(json.decode(source) as Map<String, dynamic>);
}
