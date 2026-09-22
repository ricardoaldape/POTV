import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_theme.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        const SliverAppBar(
          floating: true,
          title: Text('POTV', style: TextStyle(fontWeight: FontWeight.w900)),
          actions: [
            Padding(
              padding: EdgeInsets.all(12),
              child: Icon(Icons.person_outline),
            ),
          ],
        ),
        SliverPadding(
          padding: const EdgeInsets.all(24),
          sliver: SliverList.list(
            children: [
              Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [PotvTheme.surfaceAlt, PotvTheme.surface],
                  ),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Wrap(
                  spacing: 24,
                  runSpacing: 16,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const SizedBox(
                      width: 520,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Tu contenido. Tus fuentes. Tu dispositivo.',
                            style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          SizedBox(height: 10),
                          Text(
                            'POTV organiza TV, deportes y tus fuentes locales sin almacenar streams en nuestros servidores.',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: () => context.go('/live'),
                      icon: const Icon(Icons.live_tv_rounded),
                      label: const Text('Abrir TV'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => context.go('/sports'),
                      icon: const Icon(Icons.sports_soccer_rounded),
                      label: const Text('Sports Hub'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                'Accesos rápidos',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  _QuickCard(
                    icon: Icons.live_tv_rounded,
                    title: 'Live TV',
                    subtitle: 'Listas locales y EPG',
                    onTap: () => context.go('/live'),
                  ),
                  _QuickCard(
                    icon: Icons.sports_soccer_rounded,
                    title: 'Sports Hub',
                    subtitle: 'Eventos y resolución local',
                    onTap: () => context.go('/sports'),
                  ),
                  _QuickCard(
                    icon: Icons.search,
                    title: 'Buscar',
                    subtitle: 'Películas, series y canales',
                    onTap: () => context.go('/search'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _QuickCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _QuickCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      child: Card(
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Icon(icon, size: 36, color: PotvTheme.cyan),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        subtitle,
                        style: const TextStyle(color: Colors.white60),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
