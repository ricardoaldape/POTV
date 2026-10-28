import 'package:flutter/material.dart';
import 'package:potv/ui/branding/potv_animated_assets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/accounts/user_account.dart';
import '../../providers/user_providers.dart';

/// No navigation to content is mounted while the subscription is expired.
class SubscriptionLockedScreen extends ConsumerStatefulWidget {
  final UserAccount account;
  const SubscriptionLockedScreen({super.key, required this.account});

  @override
  ConsumerState<SubscriptionLockedScreen> createState() =>
      _SubscriptionLockedScreenState();
}

class _SubscriptionLockedScreenState
    extends ConsumerState<SubscriptionLockedScreen> {
  bool _checking = false;
  String? _message;

  Future<void> _recheck() async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _message = null;
    });
    final online = await ref
        .read(userAccountProvider.notifier)
        .refreshSubscription();
    if (!mounted) return;
    setState(() {
      _checking = false;
      _message = online
          ? 'Aún no aparece una suscripción activa para este correo.'
          : 'No pudimos comunicarnos con POTV. Comprueba tu conexión.';
    });
  }

  Future<void> _contact() async {
    final uri = Uri.parse('https://t.me/potvoficialbot');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        mounted) {
      setState(() => _message = 'No pudimos abrir el bot de POTV.');
    }
  }

  String _date(DateTime value) {
    final local = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year}';
  }

  @override
  Widget build(BuildContext context) {
    final account = widget.account;
    final expiry = account.subscriptionExpiresAt;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 470),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.lock_clock_outlined, size: 62),
                      const SizedBox(height: 16),
                      const Text(
                        'Tu acceso a POTV ha vencido',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Tu cuenta y tus perfiles siguen guardados. '
                        'Para continuar disfrutando POTV, solicita la '
                        'renovación y envía tu comprobante de pago.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 18),
                      Text(
                        account.email,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (expiry != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Venció: ${_date(expiry)}',
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                      const SizedBox(height: 26),
                      FilledButton.icon(
                        onPressed: _contact,
                        icon: const Icon(Icons.support_agent_outlined),
                        label: const Text('Solicitar activación'),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: _checking ? null : _recheck,
                        icon: _checking
                            ? const SizedBox.square(
                                dimension: 16,
                                child: PotvLoadingFlag(width: 44),
                              )
                            : const Icon(Icons.refresh_rounded),
                        label: const Text('Ya pagué: comprobar activación'),
                      ),
                      if (_message != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _message!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.amberAccent),
                        ),
                      ],
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: () =>
                            ref.read(userAccountProvider.notifier).logout(),
                        child: const Text('Cerrar sesión'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
