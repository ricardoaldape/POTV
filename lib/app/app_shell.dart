import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'app_theme.dart';

class PotvShell extends StatelessWidget {
  final Widget child;
  const PotvShell({super.key, required this.child});

  static const destinations = <({IconData icon, String label, String path})>[
    (icon: Icons.home_rounded, label: 'Inicio', path: '/'),
    (icon: Icons.live_tv_rounded, label: 'TV', path: '/live'),
    (icon: Icons.sports_soccer_rounded, label: 'Deportes', path: '/sports'),
    (icon: Icons.play_circle_outline_rounded, label: 'YT', path: '/youtube'),
    (icon: Icons.person_rounded, label: 'Mi perfil', path: '/profile'),
  ];


  int _selectedIndex(BuildContext context) {
    final path = GoRouterState.of(context).uri.path;
    final i = destinations.indexWhere((item) => item.path == path);
    if (i >= 0) return i;
    if (path == '/library' || path == '/search' || path == '/settings') {
      return 4;
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
                    context.go(destinations[index].path),
                leading: const Padding(
                  padding: EdgeInsets.fromLTRB(8, 22, 8, 18),
                  child: _PotvMark(),
                ),
                destinations: [
                  for (final item in destinations)
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
            Expanded(child: child),
          ],
        ),
      );
    }

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selected,
        onDestinationSelected: (index) =>
            context.go(destinations[index].path),
        destinations: [
          for (final item in destinations)
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
