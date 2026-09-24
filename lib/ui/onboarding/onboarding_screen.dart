import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/user_providers.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = TextEditingController();
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Crear cuenta')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text('Bienvenido a POTV. Crea tu nombre de usuario.'),
            const SizedBox(height: 12),
            TextField(controller: _controller, decoration: const InputDecoration(labelText: 'Usuario')),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _loading
                  ? null
                  : () async {
                      final username = _controller.text.trim();
                      if (username.isEmpty) return;
                      setState(() => _loading = true);
                      await ref.read(userAccountProvider.notifier).createAccount(username);
                      setState(() => _loading = false);
                    },
              child: const Text('Crear cuenta y perfil'),
            ),
          ],
        ),
      ),
    );
  }
}
