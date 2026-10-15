import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/accounts/user_account.dart';
import '../../providers/user_providers.dart';
import '../subscription/link_subscription_screen.dart';

class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  String _status(SubscriptionStatus status) => switch (status) {
    SubscriptionStatus.active => 'Activa',
    SubscriptionStatus.trial => 'Prueba gratuita',
    SubscriptionStatus.expired => 'Vencida',
    SubscriptionStatus.pending => 'Pendiente',
    SubscriptionStatus.free => 'Sin suscripción',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(userAccountProvider);
    if (account == null) return const SizedBox.shrink();

    final expiry = account.subscriptionExpiresAt?.toLocal();
    final expiryLabel = expiry == null
        ? null
        : expiry.day.toString().padLeft(2, '0') +
              '/' +
              expiry.month.toString().padLeft(2, '0') +
              '/' +
              expiry.year.toString();

    return Scaffold(
      appBar: AppBar(title: const Text('Mi cuenta')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                children: [
                  const CircleAvatar(
                    radius: 34,
                    child: Icon(Icons.person_rounded, size: 36),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    account.username,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    account.email,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          ListTile(
            leading: Icon(
              account.subscriptionStatus == SubscriptionStatus.active
                  ? Icons.verified_rounded
                  : Icons.workspace_premium_outlined,
            ),
            title: Text(_status(account.subscriptionStatus)),
            subtitle: expiryLabel == null ? null : Text('Vence ' + expiryLabel),
          ),
          ListTile(
            leading: const Icon(Icons.telegram_rounded),
            title: Text(
              account.telegramChatId == null
                  ? 'Vincular Telegram'
                  : 'Telegram vinculado',
            ),
            subtitle: const Text('Valida tu suscripción y vencimiento'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LinkSubscriptionScreen()),
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () async =>
                ref.read(userAccountProvider.notifier).logout(),
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );
  }
}
