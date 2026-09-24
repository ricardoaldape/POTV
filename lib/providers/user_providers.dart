import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../data/accounts/user_account.dart';
import '../data/accounts/user_account_repository.dart';
import '../data/accounts/user_profile.dart';

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

  UserAccountNotifier(this.ref) : super(null) {
    _load();
  }

  Future<void> _load() async {
    final repo = await ref.read(userAccountRepositoryProvider.future);
    state = repo.loadAccount();
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
    final repo = await ref.read(userAccountRepositoryProvider.future);
    await repo.clearAll();
    state = null;
    // Clear profiles and active id too
    ref.read(userProfilesProvider.notifier).clear();
    await ref.read(currentProfileIdProvider.notifier).set(null);
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
    state = state.where((p) => p.id != id).toList();
    final repo = await ref.read(userAccountRepositoryProvider.future);
    await repo.saveProfiles(state);
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
    state = id;
    final repo = await ref.read(userAccountRepositoryProvider.future);
    await repo.saveActiveProfileId(id);
  }
}
