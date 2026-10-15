import 'package:flutter_test/flutter_test.dart';
import 'package:potv/data/accounts/user_account.dart';
import 'package:potv/data/accounts/user_profile.dart';

void main() {
  test('account API payload keeps email and subscription', () {
    final account = UserAccount.fromApi({
      'id': 'acct-1',
      'email': 'cliente@example.com',
      'username': 'Cliente',
      'telegram_chat_id': '123',
      'subscription_status': 'active',
      'subscription_expires_at': '2030-01-01T00:00:00Z',
    });

    expect(account.email, 'cliente@example.com');
    expect(account.telegramChatId, '123');
    expect(account.subscriptionStatus, SubscriptionStatus.active);
    expect(account.subscriptionExpiresAt, isNotNull);
  });

  test('profile preferences serialize independently', () {
    final profile = UserProfile.create(
      accountId: 'acct-1',
      name: 'Sala',
      avatarId: 'film',
    ).copyWith(
      preferences: const ProfilePreferences(
        audioLanguage: 'es-419',
        subtitleLanguage: 'es',
        autoplayNext: false,
        sportsLanguage: 'es',
      ),
    );

    final restored = UserProfile.fromJson(profile.toJson());
    expect(restored.id, profile.id);
    expect(restored.avatarId, 'film');
    expect(restored.preferences.audioLanguage, 'es-419');
    expect(restored.preferences.autoplayNext, isFalse);
  });

  test('account storage is backwards compatible with numeric status', () {
    final account = UserAccount.fromJson({
      'id': 'legacy',
      'username': 'Legacy',
      'createdAt': '2026-01-01T00:00:00Z',
      'subscriptionStatus': 2,
    });
    expect(account.subscriptionStatus, SubscriptionStatus.active);
    expect(account.email, isEmpty);
  });
}
