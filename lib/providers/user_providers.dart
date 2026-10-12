import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../data/accounts/user_account.dart';
import '../data/accounts/user_account_repository.dart';
import '../data/accounts/user_profile.dart';
import '../data/services/subscription_verifier.dart';

final subscriptionVerifierProvider = Provider<SubscriptionVerifier>((ref) {
  return SubscriptionVerifier();
});

final userAccountRepositoryProvider = FutureProvider<UserAccountRepository>((ref) async {
  return await UserAccountRepository.getInstance();
});

final userAccountProvider = StateNotifierProvider<UserAccountNotifier, UserAccount?>(
  (ref) => UserAccountNotifier(ref),
);

final userProfilesProvider = StateNotifierProvider<UserProfilesNotifier, List<UserProfile>>(
  (ref) => UserProfilesNotifier(ref),
);

final currentProfileIdProvider = StateNotifierProvider<CurrentProfileIdNotifier, String?>(
  (ref) => CurrentProfileIdNotifier(ref),
);

class UserAccountNotifier extends StateNotifier<UserAccount?> {
  final Ref ref;
  int _subscriptionGeneration = 0;

  UserAccountNotifier(this.ref) : super(null) {
    _load();
  }

  Future<void> _load() async {
    final repo = await ref.read(userAccountRepositoryProvider.future);
    if (!mounted) return;
    final cached = repo.loadAccount();
    if (cached != null &&
        cached.subscriptionStatus == SubscriptionStatus.active &&
        (cached.subscriptionExpiresAt == null ||
            !cached.subscriptionExpiresAt!.isAfter(DateTime.now().toUtc()))) {
      // Never grant stale offline entitlements after the expiry date.
      final expired = UserAccount(
        id: cached.id,
        username: cached.username,
        createdAt: cached.createdAt,
        telegramChatId: cached.telegramChatId,
        subscriptionStatus: SubscriptionStatus.expired,
        subscriptionExpiresAt: cached.subscriptionExpiresAt,
      );
      state = expired;
      await repo.saveAccount(expired);
    } else {
      state = cached;
    }
    if (mounted) unawaited(refreshSubscription());
  }

  Future<void> createAccount(String username) async {
    final repo = await ref.read(userAccountRepositoryProvider.future);
    final acct = UserAccount.create(username);
    await repo.saveAccount(acct);
    state = acct;
    // Create initial profile for the account
    final profilesNotifier = ref.read(userProfilesProvider.notifier);
    await profilesNotifier.addProfile(username);
    // Set the active profile to the first profile if not set
    final currentId = ref.read(currentProfileIdProvider);
    if (currentId == null) {
      final profiles = ref.read(userProfilesProvider);
      if (profiles.isNotEmpty) {
        await ref.read(currentProfileIdProvider.notifier).set(profiles.first.id);
      }
    }
  }

  Future<void> logout() async {
    _subscriptionGeneration++;
    final repo = await ref.read(userAccountRepositoryProvider.future);
    await repo.clearAll();
    state = null;
    // Clear profiles and active id too
    ref.read(userProfilesProvider.notifier).clear();
    await ref.read(currentProfileIdProvider.notifier).set(null);
  }

  static SubscriptionStatus _statusOf(SubscriptionResult result) {
    final status = result.subscriptionStatus;
    if (status == 'active') {
      final expiry = result.expiresAt;
      if (expiry == null || !expiry.isAfter(DateTime.now().toUtc())) {
        return SubscriptionStatus.expired;
      }
      return SubscriptionStatus.active;
    }
    if (status == 'pending') return SubscriptionStatus.pending;
    if (status == 'expired') return SubscriptionStatus.expired;
    return SubscriptionStatus.free;
  }

  Future<void> _persistSubscription(
    UserAccount current,
    SubscriptionResult result,
  ) async {
    if (!mounted || state?.id != current.id) return;
    final updated = UserAccount(
      id: current.id,
      username: current.username,
      createdAt: current.createdAt,
      telegramChatId: current.telegramChatId,
      subscriptionStatus: _statusOf(result),
      subscriptionExpiresAt: result.expiresAt,
    );
    final repo = await ref.read(userAccountRepositoryProvider.future);
    await repo.saveAccount(updated);
    if (mounted && state?.id == current.id) state = updated;
  }

  /// Claims a one-time Telegram code. Claiming is NOT payment confirmation.
  Future<String?> linkSubscription(String code) async {
    final current = state;
    if (current == null) return 'no_account';
    final generation = ++_subscriptionGeneration;
    final result = await ref.read(subscriptionVerifierProvider).verifyCode(code);
    if (generation != _subscriptionGeneration || !mounted ||
        state?.id != current.id) {
      return 'stale_session';
    }
    if (!result.valid) return result.reason ?? 'invalid';
    await _persistSubscription(current, result);
    return null;
  }

  /// Recheck existing license without erasing known status on network failure.
  Future<void> refreshSubscription() async {
    final current = state;
    if (current == null) return;
    final generation = _subscriptionGeneration;
    final result = await ref.read(subscriptionVerifierProvider).checkLicense();
    if (generation != _subscriptionGeneration || !mounted ||
        state?.id != current.id) {
      return;
    }
    if (result.valid) {
      await _persistSubscription(current, result);
    } else if (result.reason == 'invalid_token' &&
        current.subscriptionStatus != SubscriptionStatus.free) {
      await _persistSubscription(
        current,
        const SubscriptionResult(
          valid: true,
          subscriptionStatus: 'expired',
        ),
      );
    }
  }
}

class UserProfilesNotifier extends StateNotifier<List<UserProfile>> {
  final Ref ref;

  static const _maxProfiles = 5;

  UserProfilesNotifier(this.ref) : super([]) {
    _load();
  }

  Future<void> _load() async {
    final repo = await ref.read(userAccountRepositoryProvider.future);
    state = repo.loadProfiles();
  }

  Future<UserProfile?> addProfile(String name, {bool isKids = false}) async {
    if (state.length >= _maxProfiles) return null;
    final acct = ref.read(userAccountProvider);
    if (acct == null) return null;
    final profile =
        UserProfile.create(accountId: acct.id, name: name).copyWith(isKids: isKids);
    state = [...state, profile];
    final repo = await ref.read(userAccountRepositoryProvider.future);
    await repo.saveProfiles(state);
    return profile;
  }

  Future<void> updateProfile(UserProfile updated) async {
    state = state.map((p) => p.id == updated.id ? updated : p).toList();
    final repo = await ref.read(userAccountRepositoryProvider.future);
    await repo.saveProfiles(state);
  }

  Future<void> deleteProfile(String id) async {
    // Every local account must retain at least one profile.
    if (state.length <= 1 || !state.any((profile) => profile.id == id)) {
      return;
    }
    state = state.where((p) => p.id != id).toList();
    final repo = await ref.read(userAccountRepositoryProvider.future);
    await repo.saveProfiles(state);
    await repo.deleteProfileData(id);
    final currentId = ref.read(currentProfileIdProvider);
    if (currentId == id) {
      if (state.isNotEmpty) {
        await ref.read(currentProfileIdProvider.notifier).set(state.first.id);
      } else {
        await ref.read(currentProfileIdProvider.notifier).set(null);
      }
    }
  }

  void clear() {
    state = [];
  }
}

class CurrentProfileIdNotifier extends StateNotifier<String?> {
  final Ref ref;

  CurrentProfileIdNotifier(this.ref) : super(null) {
    _load();
  }

  Future<void> _load() async {
    final repo = await ref.read(userAccountRepositoryProvider.future);
    state = repo.loadActiveProfileId();
  }

  Future<void> set(String? id) async {
    final repo = await ref.read(userAccountRepositoryProvider.future);
    await repo.saveActiveProfileId(id);
    state = id;
  }
}
