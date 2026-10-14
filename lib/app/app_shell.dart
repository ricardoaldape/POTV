import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/updates/potv_update_center.dart';
import 'package:go_router/go_router.dart';

import 'app_theme.dart';

class PotvShell extends StatefulWidget {
  final Widget child;
  const PotvShell({super.key, required this.child});

  @override
  State<PotvShell> createState() => _PotvShellState();

  static const destinations = <({IconData icon, String label, String path})>[
    (icon: Icons.home_rounded, label: 'Inicio', path: '/'),
    (icon: Icons.movie_outlined, label: 'Películas', path: '/movies'),
    (icon: Icons.tv_outlined, label: 'Series', path: '/series'),
    (icon: Icons.auto_awesome_outlined, label: 'Anime', path: '/anime'),
    (icon: Icons.live_tv_rounded, label: 'TV', path: '/live'),
    (icon: Icons.sports_soccer_rounded, label: 'Deportes', path: '/sports'),
  ];


}

class _PotvShellState extends State<PotvShell>
    with WidgetsBindingObserver {
  static const _lastCheckKey = 'potv_update_last_check_ms';
  static const _lastAttemptKey = 'potv_update_last_attempt_ms';
  static const _lastAlertedKey = 'potv_update_last_alerted_tag';
  bool _checkingUpdate = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdate());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkForUpdate();
  }

  Future<void> _checkForUpdate() async {
    if (_checkingUpdate) return;
    _checkingUpdate = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final previousSuccess = prefs.getInt(_lastCheckKey) ?? 0;
      final previousAttempt = prefs.getInt(_lastAttemptKey) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now >= previousSuccess &&
          now - previousSuccess < const Duration(hours: 12).inMilliseconds) {
        return;
      }
      if (now >= previousAttempt &&
          now - previousAttempt < const Duration(hours: 1).inMilliseconds) {
        return;
      }
      await prefs.setInt(_lastAttemptKey, now);
      final updater = PotvUpdateCenter(
        Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 12),
        )),
      );
      final installed = await updater.installedVersion();
      final channel = await updater.selectedChannel();
      final release = await updater.check(
        channel: channel,
        installed: installed,
      );
      await prefs.setInt(_lastCheckKey, now);
      if (!mounted || release == null) return;
      if (prefs.getString(_lastAlertedKey) == release.tag) return;
      await prefs.setString(_lastAlertedKey, release.tag);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('POTV ${release.versionName} disponible'),
        duration: const Duration(seconds: 12),
        action: SnackBarAction(
          label: 'Actualizar',
          onPressed: () => context.push('/update-center'),
        ),
      ));
    } catch (_) {
      // Offline launch must not block or slow down video browsing.
      // The user can run a manual check from Settings at any time.
    } finally {
      _checkingUpdate = false;
    }
  }

  int _selectedIndex(BuildContext context) {
    final path = GoRouterState.of(context).uri.path;
    final i = PotvShell.destinations.indexWhere((item) => item.path == path);
    if (i >= 0) return i;
    if (path == '/library' || path == '/search' || path == '/profile' ||
        path == '/update-center') {
      return 0;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedIndex(context);
    final wide = MediaQuery.sizeOf(context).width >= 900;

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF071016),
                border: Border(
                  right: BorderSide(
                    color: Colors.white.withValues(alpha: 0.06),
                  ),
                ),
              ),
              child: NavigationRail(
                minWidth: 74,
                selectedIndex: selected,
                groupAlignment: -0.45,
                onDestinationSelected: (index) =>
                    context.go(PotvShell.destinations[index].path),
                leading: const Padding(
                  padding: EdgeInsets.fromLTRB(8, 22, 8, 18),
                  child: _PotvMark(),
                ),
                destinations: [
                  for (final item in PotvShell.destinations)
                    NavigationRailDestination(
                      icon: Tooltip(
                        message: item.label,
                        child: Icon(item.icon),
                      ),
                      selectedIcon: Tooltip(
                        message: item.label,
                        child: Icon(item.icon),
                      ),
                      label: Text(item.label),
                    ),
                ],
              ),
            ),
            Expanded(child: widget.child),
          ],
        ),
      );
    }

    return Scaffold(
      body: widget.child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selected,
        onDestinationSelected: (index) =>
            context.go(PotvShell.destinations[index].path),
        destinations: [
          for (final item in PotvShell.destinations)
            NavigationDestination(
              icon: Icon(item.icon),
              label: item.label,
            ),
        ],
      ),
    );
  }
}

class _PotvMark extends StatelessWidget {
  const _PotvMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            PotvTheme.cyan,
            PotvTheme.cyanDeep,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: PotvTheme.cyan.withValues(alpha: 0.16),
            blurRadius: 16,
          ),
        ],
      ),
      child: const Center(
        child: Text(
          'P',
          style: TextStyle(
            color: PotvTheme.background,
            fontSize: 24,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}
