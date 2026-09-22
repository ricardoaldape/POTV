import 'package:go_router/go_router.dart';

import '../domain/models/media_item.dart';
import '../features/content/media_detail_screen.dart';
import '../features/home/home_screen.dart';
import '../features/library/library_screen.dart';
import '../features/live_tv/live_tv_screen.dart';
import '../features/player/player_screen.dart';
import '../features/search/search_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/sources/sources_screen.dart';
import '../features/sports/sports_hub_screen.dart';
import 'app_shell.dart';

final potvRouter = GoRouter(
  initialLocation: '/',
  routes: [
    ShellRoute(
      builder: (context, state, child) => PotvShell(child: child),
      routes: [
        GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
        GoRoute(path: '/live', builder: (context, state) => const LiveTvScreen()),
        GoRoute(path: '/sports', builder: (context, state) => const SportsHubScreen()),
        GoRoute(path: '/search', builder: (context, state) => const SearchScreen()),
        GoRoute(path: '/library', builder: (context, state) => const LibraryScreen()),
        GoRoute(path: '/settings', builder: (context, state) => const SettingsScreen()),
      ],
    ),
    GoRoute(
      path: '/sources',
      builder: (context, state) => const SourcesScreen(),
    ),
    GoRoute(
      path: '/detail',
      builder: (context, state) {
        final item = state.extra;
        if (item is! MediaItem) {
          throw StateError('Media item missing');
        }
        return MediaDetailScreen(item: item);
      },
    ),
    GoRoute(
      path: '/player',
      builder: (context, state) => PlayerScreen.fromExtra(state.extra),
    ),
  ],
);
