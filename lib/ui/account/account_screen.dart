import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/user_providers.dart';

class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(userAccountProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Cuenta')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: account == null
            ? const Center(child: Text('No hay cuenta'))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Usuario: ${account.username}', style: const TextStyle(fontSize: 18)),
                  const SizedBox(height: 8),
                  Text('Estado suscripción: ${account.subscriptionStatus.name}'),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () async {
                      await ref.read(userAccountProvider.notifier).logout();
                    },
                    child: const Text('Cerrar sesión'),
                  ),
                ],
              ),
      ),
    );
  }
}
