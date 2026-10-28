import 'package:flutter/material.dart';
import 'package:potv/ui/branding/potv_animated_assets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/user_providers.dart';

class LinkSubscriptionScreen extends ConsumerStatefulWidget {
  const LinkSubscriptionScreen({super.key});

  @override
  ConsumerState<LinkSubscriptionScreen> createState() =>
      _LinkSubscriptionScreenState();
}

class _LinkSubscriptionScreenState
    extends ConsumerState<LinkSubscriptionScreen> {
  final _controller = TextEditingController();
  bool _loading = false;
  String? _message;
  bool _success = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _link() async {
    final code = _controller.text.trim();
    if (code.isEmpty) return;
    setState(() {
      _loading = true;
      _message = null;
      _success = false;
    });
    final error =
        await ref.read(userAccountProvider.notifier).linkSubscription(code);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _success = error == null;
      _message = error == null
          ? 'Cuenta vinculada con Telegram.'
          : 'No pudimos validar el código. Genera uno nuevo en @potvoficialbot.';
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Vincular Telegram')),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(Icons.telegram_rounded, size: 48),
                      const SizedBox(height: 14),
                      const Text(
                        'Vincula tu suscripción',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Abre @potvoficialbot, elige “Vincular app” y escribe aquí el código temporal.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: _controller,
                        autofocus: true,
                        textCapitalization: TextCapitalization.characters,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _loading ? null : _link(),
                        decoration: const InputDecoration(
                          labelText: 'Código',
                          prefixIcon: Icon(Icons.link_rounded),
                        ),
                      ),
                      if (_message != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _message!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _success
                                ? Colors.greenAccent
                                : Colors.redAccent,
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      FilledButton.icon(
                        onPressed: _loading ? null : _link,
                        icon: const Icon(Icons.verified_user_outlined),
                        label: _loading
                            ? const SizedBox.square(
                                dimension: 20,
                                child:
                                    PotvLoadingFlag(width: 44),
                              )
                            : const Text('Vincular'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}
