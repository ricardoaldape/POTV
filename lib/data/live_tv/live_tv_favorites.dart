import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/live_channel.dart';

final liveTvFavoritesProvider =
    AsyncNotifierProvider<LiveTvFavoritesController, Set<String>>(
  LiveTvFavoritesController.new,
);

String liveChannelFavoriteKey(LiveChannel channel) {
  final epgId = channel.epgId?.trim();
  if (epgId != null && epgId.isNotEmpty) return 'epg:' + epgId;
  return 'name:' + channel.name.trim().toLowerCase();
}

class LiveTvFavoritesController extends AsyncNotifier<Set<String>> {
  static const _prefix = 'live_tv_favorite_channels_v2_';
  static const _activeProfileKey = 'potv_active_profile_id';

  Future<String> _key(SharedPreferences prefs) async {
    final profile = prefs.getString(_activeProfileKey)?.trim();
    final suffix = profile != null && profile.isNotEmpty ? profile : 'guest';
    return _prefix + suffix;
  }

  @override
  Future<Set<String>> build() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(await _key(prefs)) ?? const <String>[]).toSet();
  }

  Future<void> toggle(LiveChannel channel) async {
    final current = {...(state.asData?.value ?? const <String>{})};
    final channelKey = liveChannelFavoriteKey(channel);
    if (!current.add(channelKey)) current.remove(channelKey);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(await _key(prefs), current.toList()..sort());
    state = AsyncData(current);
  }
}
