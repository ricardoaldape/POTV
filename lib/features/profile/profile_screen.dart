import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers/user_providers.dart';
import '../../data/accounts/user_account.dart';
import 'potv_avatars.dart';

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
                  PotvAvatar(avatarId: profiles.where((p) => p.id == activeId).isEmpty ? 'default' : profiles.firstWhere((p) => p.id == activeId).avatarId, radius: 30),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(account?.username ?? 'Sin cuenta', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 4),
                        const Text('Perfiles independientes en este dispositivo.', style: TextStyle(color: Colors.white60)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.verified_user_rounded),
              title: Text('Suscripción: ${switch (account?.subscriptionStatus) {
                SubscriptionStatus.active => 'Activa',
                SubscriptionStatus.pending => 'Pendiente',
                SubscriptionStatus.expired => 'Vencida',
                _ => 'Sin activar',
              }}'),
              subtitle: account?.subscriptionExpiresAt == null
                  ? const Text('Vincula tu suscripción de Telegram.')
                  : Text('Vence: ${account!.subscriptionExpiresAt!.toLocal()}'),
              trailing: FilledButton.tonal(
                onPressed: account == null
                    ? null
                    : () => _linkSubscription(context, ref),
                child: const Text('Vincular'),
              ),
            ),
          ),
          TextButton.icon(
            onPressed: () async {
              await launchUrl(
                Uri.parse('https://t.me/potvoficialbot'),
                mode: LaunchMode.externalApplication,
              );
            },
            icon: const Icon(Icons.open_in_new_rounded),
            label: const Text('Abrir bot de Telegram'),
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
                      child: PotvAvatar(avatarId: p.avatarId, radius: selected ? 30 : 26),
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
                        if (!context.mounted || name == null || name.isEmpty) return;
                        final avatar = await _chooseAvatar(context, current: p.avatarId);
                        if (avatar == null) return;
                        await ref.read(userProfilesProvider.notifier).updateProfile(
                          p.copyWith(name: name, avatarId: avatar),
                        );
                      },
                child: const Text('Editar'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: profiles.length <= 1
                    ? null
                    : () async {
                        final p = profiles.firstWhere((e) => e.id == activeId, orElse: () => profiles.first);
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (dialogContext) => AlertDialog(
                            title: const Text('Eliminar perfil'),
                            content: Text(
                              '¿Eliminar el perfil "${p.name}"? Se borrarán su historial y sus favoritos guardados en este dispositivo.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(dialogContext).pop(false),
                                child: const Text('Cancelar'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.of(dialogContext).pop(true),
                                child: const Text('Eliminar'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed != true || !context.mounted) return;
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
            leading: const Icon(Icons.settings_rounded),
            title: const Text('Ajustes'),
            onTap: () => context.push('/settings'),
          ),
        ],
      ),
    );
  }

  Future<void> _linkSubscription(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Vincular suscripción'),
        content: TextField(
          controller: controller,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'Código de Telegram',
            hintText: '12 caracteres',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext)
                .pop(controller.text.trim()),
            child: const Text('Verificar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (code == null || code.isEmpty || !context.mounted) return;
    final reason = await ref.read(userAccountProvider.notifier)
        .linkSubscription(code);
    if (!context.mounted) return;
    final account = ref.read(userAccountProvider);
    final message = reason != null
        ? 'No se pudo vincular el código: $reason'
        : account?.subscriptionStatus == SubscriptionStatus.active
            ? 'Suscripción vinculada y activa.'
            : 'Cuenta vinculada. La suscripción aún no está activa.';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<String?> _chooseAvatar(BuildContext context, {required String current}) {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Elige tu avatar'),
        content: SizedBox(
          width: 340,
          child: GridView.count(
            shrinkWrap: true,
            crossAxisCount: 4,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            children: [
              for (final id in PotvAvatars.icons.keys)
                IconButton(
                  tooltip: id,
                  onPressed: () => Navigator.of(dialogContext).pop(id),
                  icon: PotvAvatar(avatarId: id, radius: 24),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
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
