import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/user_providers.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profiles = ref.watch(userProfilesProvider);
    final account = ref.watch(userAccountProvider);
    final activeId = ref.watch(currentProfileIdProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Mi perfil')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  const CircleAvatar(radius: 30, child: Icon(Icons.person_rounded, size: 32)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(account?.username ?? 'Sin cuenta', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 4),
                        const Text('Cuenta y sincronización entre dispositivos se conectarán aquí.', style: TextStyle(color: Colors.white60)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 100,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemBuilder: (context, index) {
                final p = profiles[index];
                final selected = p.id == activeId;
                return Column(
                  children: [
                    GestureDetector(
                      onTap: () => ref.read(currentProfileIdProvider.notifier).set(p.id),
                      child: CircleAvatar(radius: selected ? 30 : 26, child: Text(p.name.substring(0, 1).toUpperCase())),
                    ),
                    const SizedBox(height: 6),
                    Text(p.name, style: TextStyle(color: selected ? Colors.white : Colors.white60)),
                  ],
                );
              },
              separatorBuilder: (context, index) => const SizedBox(width: 12),
              itemCount: profiles.length,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              ElevatedButton(
                onPressed: profiles.length >= 5
                    ? null
                    : () async {
                        // Add profile
                        final name = await _askForName(context);
                        if (name != null && name.isNotEmpty) {
                          await ref.read(userProfilesProvider.notifier).addProfile(name);
                        }
                      },
                child: const Text('Añadir'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: profiles.isEmpty
                    ? null
                    : () async {
                        final p = profiles.firstWhere((e) => e.id == activeId, orElse: () => profiles.first);
                        final name = await _askForName(context, initial: p.name);
                        if (name != null && name.isNotEmpty) {
                          await ref.read(userProfilesProvider.notifier).updateProfile(p.copyWith(name: name));
                        }
                      },
                child: const Text('Editar'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: profiles.isEmpty
                    ? null
                    : () async {
                        final p = profiles.firstWhere((e) => e.id == activeId, orElse: () => profiles.first);
                        await ref.read(userProfilesProvider.notifier).deleteProfile(p.id);
                      },
                child: const Text('Eliminar'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ListTile(
            leading: const Icon(Icons.bookmark_rounded),
            title: const Text('Mi lista e historial'),
            onTap: () => context.push('/library'),
          ),
          ListTile(
            leading: const Icon(Icons.search_rounded),
            title: const Text('Buscar en POTV'),
            onTap: () => context.push('/search'),
          ),
          ListTile(
            leading: const Icon(Icons.extension_rounded),
            title: const Text('Fuentes y extensiones'),
            onTap: () => context.push('/sources'),
          ),
          ListTile(
            leading: const Icon(Icons.settings_rounded),
            title: const Text('Ajustes'),
            onTap: () => context.push('/settings'),
          ),
        ],
      ),
    );
  }

  Future<String?> _askForName(BuildContext context, {String? initial}) async {
    final controller = TextEditingController(text: initial);
    return showDialog<String?>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nombre del perfil'),
        content: TextField(controller: controller, decoration: const InputDecoration(labelText: 'Nombre')),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(null), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.of(context).pop(controller.text.trim()), child: const Text('Aceptar')),
        ],
      ),
    );
  }
}
