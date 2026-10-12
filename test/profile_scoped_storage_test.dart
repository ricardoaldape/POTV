import 'package:flutter_test/flutter_test.dart';
import 'package:potv/data/accounts/profile_scoped_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final profiles = '[{"id":"first"},{"id":"second"}]';

  test('legacy watch history migrates only to the original first profile',
      () async {
    SharedPreferences.setMockInitialValues({
      ProfileScopedStorage.activeProfileKey: 'second',
      ProfileScopedStorage.profilesKey: profiles,
      ProfileScopedStorage.historyKey: '[{"id":"old"}]',
    });
    final prefs = await SharedPreferences.getInstance();
    final activeKey = await ProfileScopedStorage.activeKey(
      prefs, ProfileScopedStorage.historyKey,
    );
    expect(
      activeKey,
      ProfileScopedStorage.scopedKey(
        ProfileScopedStorage.historyKey, 'second',
      ),
    );
    expect(prefs.getString(activeKey), isNull);
    expect(
      prefs.getString(ProfileScopedStorage.scopedKey(
        ProfileScopedStorage.historyKey, 'first')),
      '[{"id":"old"}]',
    );
    expect(prefs.getString(ProfileScopedStorage.historyKey), isNull);
  });

  test('legacy TV favorites migrate without crossing profiles', () async {
    SharedPreferences.setMockInitialValues({
      ProfileScopedStorage.activeProfileKey: 'second',
      ProfileScopedStorage.profilesKey: profiles,
      ProfileScopedStorage.liveTvFavoritesKey: ['epg:test'],
    });
    final prefs = await SharedPreferences.getInstance();
    await ProfileScopedStorage.activeKey(
      prefs, ProfileScopedStorage.liveTvFavoritesKey,
    );
    expect(
      prefs.getStringList(ProfileScopedStorage.scopedKey(
        ProfileScopedStorage.liveTvFavoritesKey, 'first')),
      ['epg:test'],
    );
    expect(
      prefs.getStringList(ProfileScopedStorage.scopedKey(
        ProfileScopedStorage.liveTvFavoritesKey, 'second')),
      isNull,
    );
  });

  test('deleting one profile preserves all other profile data', () async {
    SharedPreferences.setMockInitialValues({
      ProfileScopedStorage.scopedKey(ProfileScopedStorage.historyKey, 'first'):
          'first-history',
      ProfileScopedStorage.scopedKey(ProfileScopedStorage.historyKey, 'second'):
          'second-history',
      ProfileScopedStorage.scopedKey(
          ProfileScopedStorage.liveTvFavoritesKey, 'first'): ['x'],
      ProfileScopedStorage.scopedKey(
          ProfileScopedStorage.liveTvFavoritesKey, 'second'): ['y'],
    });
    final prefs = await SharedPreferences.getInstance();
    await ProfileScopedStorage.clearProfile(prefs, 'first');
    expect(
      prefs.getString(ProfileScopedStorage.scopedKey(
        ProfileScopedStorage.historyKey, 'first')),
      isNull,
    );
    expect(
      prefs.getString(ProfileScopedStorage.scopedKey(
        ProfileScopedStorage.historyKey, 'second')),
      'second-history',
    );
    expect(
      prefs.getStringList(ProfileScopedStorage.scopedKey(
        ProfileScopedStorage.liveTvFavoritesKey, 'second')),
      ['y'],
    );
  });
}
