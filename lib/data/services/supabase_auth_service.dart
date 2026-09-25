// TODO: Añadir supabase_flutter al pubspec.yaml
// TODO(main.dart):
// await Supabase.initialize(url: 'TU_SUPABASE_URL', anonKey: 'TU_SUPABASE_ANON_KEY');
// final authService = SupabaseAuthService();
// // Usa authService/current session para decidir entre LoginScreen y la app.
import 'package:supabase_flutter/supabase_flutter.dart';

import '../accounts/user_account.dart';
import '../accounts/user_profile.dart';

class SupabaseAuthService {
  SupabaseAuthService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<UserAccount> signUp(
    String email,
    String password,
    String username,
  ) async {
    final response = await _client.auth.signUp(
      email: email.trim(),
      password: password,
      data: {'username': username.trim()},
    );
    final user = response.user;
    if (user == null) {
      throw const AuthException('No se pudo crear la cuenta.');
    }

    await _client.from('accounts').upsert({
      'id': user.id,
      'email': email.trim(),
      'username': username.trim(),
      'subscription_status': 'free',
    });

    await _client.from('profiles').insert({
      'account_id': user.id,
      'name': username.trim(),
      'avatar_id': 'default',
      'is_kids': false,
      'language': 'es',
    });

    await _client.from('user_settings').upsert({
      'account_id': user.id,
      'preferred_language': 'es',
      'preferred_quality': 'auto',
      'autoplay_enabled': true,
    });

    return _loadAccount(user.id);
  }

  Future<UserAccount> signIn(String email, String password) async {
    final response = await _client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
    final user = response.user;
    if (user == null) {
      throw const AuthException('No se pudo iniciar sesión.');
    }
    return _loadAccount(user.id);
  }

  Future<void> signOut() => _client.auth.signOut();

  User? currentUser() => _client.auth.currentUser;

  Future<UserAccount?> loadCurrentAccount() async {
    final user = currentUser();
    if (user == null) return null;
    return _loadAccount(user.id);
  }

  Future<List<UserProfile>> loadProfiles() async {
    final user = currentUser();
    if (user == null) return const [];
    final rows = await _client
        .from('profiles')
        .select()
        .eq('account_id', user.id)
        .order('name');
    return (rows as List<dynamic>)
        .map((row) => UserProfile.fromSupabase(
              Map<String, dynamic>.from(row as Map),
            ))
        .toList();
  }

  Future<void> saveSettings({
    String? preferredLanguage,
    String? preferredQuality,
    bool? autoplayEnabled,
  }) async {
    final user = currentUser();
    if (user == null) throw const AuthException('No hay una sesión activa.');

    final values = <String, dynamic>{'account_id': user.id};
    if (preferredLanguage != null) {
      values['preferred_language'] = preferredLanguage;
    }
    if (preferredQuality != null) {
      values['preferred_quality'] = preferredQuality;
    }
    if (autoplayEnabled != null) {
      values['autoplay_enabled'] = autoplayEnabled;
    }
    await _client.from('user_settings').upsert(values);
  }

  Future<Map<String, dynamic>?> loadSettings() async {
    final user = currentUser();
    if (user == null) return null;
    final row = await _client
        .from('user_settings')
        .select()
        .eq('account_id', user.id)
        .maybeSingle();
    return row == null ? null : Map<String, dynamic>.from(row);
  }

  Future<void> saveProfile(UserProfile profile) async {
    await _client.from('profiles').upsert(profile.toSupabase());
  }

  Future<void> deleteProfile(String profileId) async {
    await _client.from('profiles').delete().eq('id', profileId);
  }

  Future<UserAccount> _loadAccount(String userId) async {
    final row =
        await _client.from('accounts').select().eq('id', userId).single();
    return UserAccount.fromSupabase(Map<String, dynamic>.from(row));
  }
}
