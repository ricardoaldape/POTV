import '../services/supabase_auth_service.dart';
import 'user_account.dart';
import 'user_profile.dart';

/// Supabase-backed account repository.
///
/// The public class name is retained so existing consumers can migrate without
/// changing their repository dependency. Synchronous legacy reads return the
/// most recently loaded in-memory state; call [refresh] after authentication.
class UserAccountRepository {
  UserAccountRepository._(this._auth);

  final SupabaseAuthService _auth;
  UserAccount? _account;
  List<UserProfile> _profiles = const [];
  String? _activeProfileId;

  static Future<UserAccountRepository> getInstance() async {
    final repository = UserAccountRepository._(SupabaseAuthService());
    await repository.refresh();
    return repository;
  }

  Future<void> refresh() async {
    _account = await _auth.loadCurrentAccount();
    _profiles = _account == null ? const [] : await _auth.loadProfiles();
    if (_profiles.isNotEmpty &&
        !_profiles.any((profile) => profile.id == _activeProfileId)) {
      _activeProfileId = _profiles.first.id;
    }
  }

  Future<void> saveAccount(UserAccount account) async {
    // Account identity/subscription data is server-owned. Refresh from
    // Supabase instead of persisting an unauthenticated local copy.
    _account = account;
  }

  UserAccount? loadAccount() => _account;

  Future<void> saveProfiles(List<UserProfile> profiles) async {
    for (final profile in profiles) {
      await _auth.saveProfile(profile);
    }
    final remote = await _auth.loadProfiles();
    final remoteIds = remote.map((profile) => profile.id).toSet();
    for (final profile in remote) {
      if (!profiles.any((candidate) => candidate.id == profile.id)) {
        await _auth.deleteProfile(profile.id);
      }
    }
    _profiles = profiles.where((profile) => remoteIds.contains(profile.id) || !remoteIds.contains(profile.id)).toList();
  }

  List<UserProfile> loadProfiles() => List.unmodifiable(_profiles);

  Future<void> saveActiveProfileId(String? id) async {
    _activeProfileId = id;
  }

  String? loadActiveProfileId() => _activeProfileId;

  Future<void> clearAll() async {
    await _auth.signOut();
    _account = null;
    _profiles = const [];
    _activeProfileId = null;
  }
}
