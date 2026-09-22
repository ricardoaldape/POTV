import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/live_channel.dart';

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
  static const _key = 'live_tv_favorite_channels';

  @override
  Future<Set<String>> build() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_key) ?? const <String>[]).toSet();
  }

  Future<void> toggle(LiveChannel channel) async {
    final current = {...(state.asData?.value ?? const <String>{})};
    final key = liveChannelFavoriteKey(channel);

    if (!current.add(key)) {
      current.remove(key);
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, current.toList()..sort());
    state = AsyncData(current);
  }
}
