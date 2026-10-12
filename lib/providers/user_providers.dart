import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../data/accounts/account_auth_service.dart';
import '../data/accounts/user_account.dart';
import '../data/accounts/user_account_repository.dart';
import '../data/accounts/user_profile.dart';
import '../data/services/subscription_verifier.dart';

final userAccountRepositoryProvider = FutureProvider<UserAccountRepository>(
  (ref) => UserAccountRepository.getInstance(),
);

final accountAuthServiceProvider = Provider<AccountAuthService>(
  (ref) => AccountAuthService(),
);

final userAccountProvider =
    StateNotifierProvider<UserAccountNotifier, UserAccount?>(
  (ref) => UserAccountNotifier(ref),
);

final userProfilesProvider =
    StateNotifierProvider<UserProfilesNotifier, List<UserProfile>>(
  (ref) => UserProfilesNotifier(ref),
);

final currentProfileIdProvider =
    StateNotifierProvider<CurrentProfileIdNotifier, String?>(
  (ref) => CurrentProfileIdNotifier(ref),
);

final activeProfileProvider = Provider<UserProfile?>((ref) {
  final id = ref.watch(currentProfileIdProvider);
  final profiles = ref.watch(userProfilesProvider);
  for (final profile in profiles) {
    if (profile.id == id) return profile;
  }
  return profiles.isEmpty ? null : profiles.first;
});

final authBootstrapProvider = FutureProvider<void>((ref) async {
  await ref.read(userAccountProvider.notifier).restore();
});

class UserAccountNotifier extends StateNotifier<UserAccount?> {
  final Ref ref;
  UserAccountNotifier(this.ref) : super(null);

  Future<void> restore() async {
    final repo = await ref.read(userAccountRepositoryProvider.future);
    final cached = repo.loadAccount();
    state = cached;
    try {
      final remote = await ref.read(accountAuthServiceProvider).restore();
      if (remote == null) {
        state = null;
        await repo.clearSession();
        ref.read(userProfilesProvider.notifier).clearVisible();
        return;
      }
      state = remote;
      await repo.saveAccount(remote);
      await ref.read(userProfilesProvider.notifier).loadForAccount(remote.id);
    } catch (_) {
      if (cached != null) {
        await ref.read(userProfilesProvider.notifier).loadForAccount(cached.id);
      }
    }
  }

  Future<void> register({
    required String email,
    required String password,
    required String name,
  }) async {
    final auth = ref.read(accountAuthServiceProvider);
    final account = await auth.register(email: email, password: password, name: name);
    final repo = await ref.read(userAccountRepositoryProvider.future);
    state = account;
    await repo.saveAccount(account);
    await ref.read(userProfilesProvider.notifier).loadForAccount(account.id);
    if (ref.read(userProfilesProvider).isEmpty) {
      final profile = await ref.read(userProfilesProvider.notifier).addProfile(name);
      if (profile != null) {
        await ref.read(currentProfileIdProvider.notifier).set(profile.id);
      }
    }
  }

  Future<void> login({
    required String email,
    required String password,
  }) async {
    final account =
        await ref.read(accountAuthServiceProvider).login(email: email, password: password);
    final repo = await ref.read(userAccountRepositoryProvider.future);
    state = account;
    await repo.saveAccount(account);
    await ref.read(userProfilesProvider.notifier).loadForAccount(account.id);
    final profiles = ref.read(userProfilesProvider);
    if (profiles.isEmpty) {
      final seedName = account.username.trim().isEmpty ? 'Perfil 1' : account.username;
      final profile = await ref.read(userProfilesProvider.notifier).addProfile(seedName);
      await ref.read(currentProfileIdProvider.notifier).set(profile?.id);
    } else {
      final saved = repo.loadActiveProfileId();
      final valid = profiles.any((profile) => profile.id == saved);
      await ref.read(currentProfileIdProvider.notifier).set(
            valid ? saved : profiles.first.id,
          );
    }
  }

  Future<void> logout() async {
    await ref.read(accountAuthServiceProvider).logout();
    final repo = await ref.read(userAccountRepositoryProvider.future);
    await repo.clearSession();
    state = null;
    ref.read(userProfilesProvider.notifier).clearVisible();
    await ref.read(currentProfileIdProvider.notifier).set(null);
  }

  Future<String?> linkSubscription(String code) async {
    final current = state;
    if (current == null) return 'no_account';
    final token = await ref.read(accountAuthServiceProvider).sessionToken();
    final result = await SubscriptionVerifier().verifyCode(
      code,
      accountSessionToken: token,
    );
    if (!result.linked) return result.reason ?? 'invalid';

    final status = SubscriptionStatus.values.firstWhere(
      (value) => value.name == result.status,
      orElse: () => SubscriptionStatus.free,
    );
    final updated = current.copyWith(
      telegramChatId: result.telegramChatId,
      subscriptionStatus: status,
      subscriptionExpiresAt: result.expiresAt,
      clearSubscriptionExpiresAt: result.expiresAt == null,
    );
    state = updated;
    final repo = await ref.read(userAccountRepositoryProvider.future);
    await repo.saveAccount(updated);
    return null;
  }
}

class UserProfilesNotifier extends StateNotifier<List<UserProfile>> {
  final Ref ref;
  static const _maxProfiles = 5;
  UserProfilesNotifier(this.ref) : super(const []);

  Future<void> loadForAccount(String accountId) async {
    final repo = await ref.read(userAccountRepositoryProvider.future);
    state = repo.loadProfiles(accountId);
    final saved = repo.loadActiveProfileId();
    if (state.isNotEmpty && !state.any((profile) => profile.id == saved)) {
      await ref.read(currentProfileIdProvider.notifier).set(state.first.id);
    }
  }

  Future<UserProfile?> addProfile(
    String name, {
    String avatarId = 'ocean',
    bool isKids = false,
  }) async {
    if (state.length >= _maxProfiles || name.trim().isEmpty) return null;
    final account = ref.read(userAccountProvider);
    if (account == null) return null;
    final profile = UserProfile.create(
      accountId: account.id,
      name: name.trim(),
      avatarId: avatarId,
      isKids: isKids,
    );
    state = [...state, profile];
    final repo = await ref.read(userAccountRepositoryProvider.future);
    await repo.saveProfiles(account.id, state);
    return profile;
  }

  Future<void> updateProfile(UserProfile updated) async {
    final account = ref.read(userAccountProvider);
    if (account == null || updated.accountId != account.id) return;
    state = [for (final p in state) if (p.id == updated.id) updated else p];
    final repo = await ref.read(userAccountRepositoryProvider.future);
    await repo.saveProfiles(account.id, state);
  }

  Future<void> deleteProfile(String id) async {
    if (state.length <= 1) return;
    final account = ref.read(userAccountProvider);
    if (account == null) return;
    state = state.where((profile) => profile.id != id).toList(growable: false);
    final repo = await ref.read(userAccountRepositoryProvider.future);
    await repo.saveProfiles(account.id, state);
    if (ref.read(currentProfileIdProvider) == id && state.isNotEmpty) {
      await ref.read(currentProfileIdProvider.notifier).set(state.first.id);
    }
  }

  void clearVisible() => state = const [];
}

class CurrentProfileIdNotifier extends StateNotifier<String?> {
  final Ref ref;
  CurrentProfileIdNotifier(this.ref) : super(null);

  Future<void> set(String? id) async {
    state = id;
    final repo = await ref.read(userAccountRepositoryProvider.future);
    await repo.saveActiveProfileId(id);
  }
}
