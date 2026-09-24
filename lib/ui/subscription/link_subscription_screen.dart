import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/user_providers.dart';

class LinkSubscriptionScreen extends ConsumerStatefulWidget {
  const LinkSubscriptionScreen({super.key});

  @override
  ConsumerState<LinkSubscriptionScreen> createState() => _LinkSubscriptionScreenState();
}

class _LinkSubscriptionScreenState extends ConsumerState<LinkSubscriptionScreen> {
  final _controller = TextEditingController();
  bool _loading = false;
  String? _message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Vincular suscripción')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text('Introduce tu código de suscripción (formato POTV-XXXXXX)'),
            const SizedBox(height: 12),
            TextField(controller: _controller, decoration: const InputDecoration(labelText: 'Código')),
            const SizedBox(height: 12),
            if (_message != null) Text(_message!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _loading
                  ? null
                  : () async {
                      final code = _controller.text.trim();
                      if (code.isEmpty) return;
                      setState(() => _loading = true);
                      final err = await ref.read(userAccountProvider.notifier).linkSubscription(code);
                      setState(() {
                        _loading = false;
                        if (err == null) {
                          _message = 'Vinculación exitosa';
                        } else {
                          _message = 'Error: $err';
                        }
                      });
                    },
              child: _loading ? const CircularProgressIndicator() : const Text('Vincular'),
            ),
          ],
        ),
      ),
    );
  }
}
