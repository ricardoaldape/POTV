import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class PotvShell extends StatelessWidget {
  final Widget child;
  const PotvShell({super.key, required this.child});

  static const destinations = <({IconData icon, String label, String path})>[
    (icon: Icons.home_rounded, label: 'Inicio', path: '/'),
    (icon: Icons.live_tv_rounded, label: 'TV', path: '/live'),
    (icon: Icons.sports_soccer_rounded, label: 'Deportes', path: '/sports'),
    (icon: Icons.search_rounded, label: 'Buscar', path: '/search'),
    (icon: Icons.bookmark_rounded, label: 'Mi lista', path: '/library'),
    (icon: Icons.settings_rounded, label: 'Ajustes', path: '/settings'),
  ];

  int _selectedIndex(BuildContext context) {
    final path = GoRouterState.of(context).uri.path;
    final i = destinations.indexWhere((item) => item.path == path);
    return i < 0 ? 0 : i;
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedIndex(context);
    final wide = MediaQuery.sizeOf(context).width >= 900;

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: selected,
              extended: MediaQuery.sizeOf(context).width >= 1200,
              onDestinationSelected: (index) =>
                  context.go(destinations[index].path),
              leading: const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  'POTV',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                ),
              ),
              destinations: [
                for (final item in destinations)
                  NavigationRailDestination(
                    icon: Icon(item.icon),
                    selectedIcon: Icon(item.icon),
                    label: Text(item.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: child),
          ],
        ),
      );
    }

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selected.clamp(0, 4),
        onDestinationSelected: (index) =>
            context.go(destinations[index].path),
        destinations: [
          for (final item in destinations.take(5))
            NavigationDestination(icon: Icon(item.icon), label: item.label),
        ],
      ),
    );
  }
}
