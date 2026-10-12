import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/live_channel.dart';
import '../../providers/user_providers.dart';
import '../accounts/profile_scoped_storage.dart';

final liveTvFavoritesProvider =
    AsyncNotifierProvider<LiveTvFavoritesController, Set<String>>(
  LiveTvFavoritesController.new,
);

String liveChannelFavoriteKey(LiveChannel channel) {
  final epgId = channel.epgId?.trim();
  if (epgId != null && epgId.isNotEmpty) return 'epg:$epgId';
  return 'name:${channel.name.trim().toLowerCase()}';
}

class LiveTvFavoritesController extends AsyncNotifier<Set<String>> {
  static const _key = ProfileScopedStorage.liveTvFavoritesKey;

  @override
  Future<Set<String>> build() async {
    ref.watch(currentProfileIdProvider);
    final prefs = await SharedPreferences.getInstance();
    final key = await ProfileScopedStorage.activeKey(prefs, _key);
    return (prefs.getStringList(key) ?? const <String>[]).toSet();
  }

  Future<void> toggle(LiveChannel channel) async {
    final current = {...(state.asData?.value ?? const <String>{})};
    final key = liveChannelFavoriteKey(channel);

    if (!current.add(key)) {
      current.remove(key);
    }

    final prefs = await SharedPreferences.getInstance();
    final storageKey = await ProfileScopedStorage.activeKey(prefs, _key);
    await prefs.setStringList(storageKey, current.toList()..sort());
    state = AsyncData(current);
  }
}
