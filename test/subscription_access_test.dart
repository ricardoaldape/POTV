import 'package:flutter_test/flutter_test.dart';
import 'package:potv/data/accounts/user_account.dart';

void main() {
  UserAccount account(String status, DateTime expiry) => UserAccount.fromApi({
    'id': 'test-1',
    'email': 'qa@example.com',
    'username': 'QA',
    'created_at': DateTime.now().toUtc().toIso8601String(),
    'subscription_status': status,
    'subscription_expires_at': expiry.toIso8601String(),
  });

  test('trial grants access while valid, but never shows paid warning', () {
    final a = account(
      'trial',
      DateTime.now().toUtc().add(const Duration(days: 2)),
    );
    expect(a.hasViewingAccess, isTrue);
    expect(a.renewalWarning, isFalse);
  });

  test('paid membership shows warning in final ten days', () {
    final a = account(
      'active',
      DateTime.now().toUtc().add(const Duration(days: 9)),
    );
    expect(a.hasViewingAccess, isTrue);
    expect(a.renewalWarning, isTrue);
  });

  test('paid membership does not show warning earlier than ten days', () {
    final a = account(
      'active',
      DateTime.now().toUtc().add(const Duration(days: 11)),
    );
    expect(a.hasViewingAccess, isTrue);
    expect(a.renewalWarning, isFalse);
  });

  test('expired accounts cannot watch even if status says active', () {
    final a = account(
      'active',
      DateTime.now().toUtc().subtract(const Duration(seconds: 2)),
    );
    expect(a.hasViewingAccess, isFalse);
    expect(a.remainingDays, 0);
  });

  test('new accounts without a paid or trial grant are blocked', () {
    final a = account(
      'free',
      DateTime.now().toUtc().add(const Duration(days: 5)),
    );
    expect(a.hasViewingAccess, isFalse);
  });
}
