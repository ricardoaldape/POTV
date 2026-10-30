import 'package:flutter/material.dart';
import 'package:potv/ui/branding/potv_animated_assets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/accounts/account_auth_service.dart';
import '../../providers/user_providers.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _verificationCode = TextEditingController();
  bool _awaitingEmailVerification = false;
  bool _register = false;
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    _verificationCode.dispose();
    super.dispose();
  }

  String _message(Object error) {
    final code = error is AccountAuthException ? error.code : 'network';
    return switch (code) {
      'account_exists' => 'Ya existe una cuenta con ese correo.',
      'invalid_email' => 'Escribe un correo válido.',
      'invalid_password' => 'La contraseña debe tener al menos 8 caracteres.',
      'invalid_name' => 'Escribe un nombre para tu perfil.',
      'invalid_credentials' => 'Correo o contraseña incorrectos.',
      'invalid_verification_code' => 'Código incorrecto. Revisa tu correo.',
      'verification_expired' => 'El código venció. Vuelve a iniciar el registro.',
      'verification_rate_limited' => 'Espera un minuto para solicitar otro código.',
      'verification_attempts_exceeded' => 'Demasiados intentos. Solicita un nuevo código.',
      'verification_unavailable' => 'La verificación por correo no está disponible.',
      'verification_delivery_failed' => 'No pudimos enviar el correo. Inténtalo nuevamente.',
      'invalid_recovery_code' => 'El código no es válido.',
      'expired_recovery_code' => 'El código venció. Solicita uno nuevo.',
      _ => 'No pudimos conectar con POTV. Revisa tu conexión e inténtalo de nuevo.',
    };
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final password = _password.text;
    final name = _name.text.trim();
    if (!email.contains('@') ||
        password.length < 8 ||
        (_register && name.length < 2)) {
      setState(() => _error = 'Revisa los datos antes de continuar.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_register) {
        await ref.read(accountAuthServiceProvider).requestEmailRegistration(
              email: email, password: password, name: name,
            );
        if (mounted) setState(() => _awaitingEmailVerification = true);
      } else {
        await ref.read(userAccountProvider.notifier).login(
              email: email,
              password: password,
            );
      }
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _confirmRegistration() async {
    if (!RegExp(r'^\d{6}$').hasMatch(_verificationCode.text.trim())) {
      setState(() => _error = 'Introduce el código de 6 dígitos recibido en tu correo.');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await ref.read(accountAuthServiceProvider).verifyRegistrationEmail(
        email: _email.text.trim(), code: _verificationCode.text.trim(),
      );
      await ref.read(userAccountProvider.notifier).login(
        email: _email.text.trim(), password: _password.text,
      );
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resendRegistration() async {
    setState(() { _loading = true; _error = null; });
    try {
      await ref.read(accountAuthServiceProvider).resendRegistrationEmail(_email.text.trim());
      if (mounted) setState(() => _error = 'Enviamos un código nuevo a tu correo.');
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _recover() async {
    final email = TextEditingController(text: _email.text.trim());
    final code = TextEditingController();
    final nextPassword = TextEditingController();
    var sent = false;
    String? error;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Recuperar acceso'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Correo',
                    prefixIcon: Icon(Icons.mail_outline_rounded),
                  ),
                ),
                if (sent) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Si tu cuenta está vinculada, recibirás un código privado en el bot de POTV.',
                    style: TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: code,
                    textCapitalization: TextCapitalization.characters,
                    decoration:
                        const InputDecoration(labelText: 'Código de recuperación'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nextPassword,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Nueva contraseña'),
                  ),
                ],
                if (error != null) ...[
                  const SizedBox(height: 10),
                  Text(error!,
                      style: const TextStyle(color: Colors.redAccent)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  final auth = ref.read(accountAuthServiceProvider);
                  if (!sent) {
                    await auth.requestRecovery(email.text.trim());
                    setDialogState(() {
                      sent = true;
                      error = null;
                    });
                    return;
                  }
                  if (code.text.trim().isEmpty || nextPassword.text.length < 8) {
                    setDialogState(() =>
                        error = 'Completa el código y la nueva contraseña.');
                    return;
                  }
                  await auth.confirmRecovery(
                    email: email.text.trim(),
                    code: code.text.trim(),
                    newPassword: nextPassword.text,
                  );
                  if (dialogContext.mounted) {
                    Navigator.of(dialogContext).pop();
                  }
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Contraseña actualizada. Ya puedes iniciar sesión.',
                        ),
                      ),
                    );
                  }
                } catch (value) {
                  setDialogState(() => error = _message(value));
                }
              },
              child: Text(sent ? 'Cambiar contraseña' : 'Enviar código'),
            ),
          ],
        ),
      ),
    );

    email.dispose();
    code.dispose();
    nextPassword.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 760;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: wide ? 480 : 420),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: AutofillGroup(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'POTV',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 42,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _awaitingEmailVerification ? 'Confirma tu correo' : (_register ? 'Crea tu cuenta' : 'Bienvenido de nuevo'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 24),
                        if (_awaitingEmailVerification) ...[
                          Text('Enviamos un código a ${_email.text.trim()}. La prueba gratis comenzará cuando confirmes el correo.'),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _verificationCode,
                            keyboardType: TextInputType.number,
                            maxLength: 6,
                            decoration: const InputDecoration(labelText: 'Código de 6 dígitos'),
                          ),
                        ] else if (_register) ...[
                          TextField(
                            controller: _name,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.name],
                            decoration: const InputDecoration(
                              labelText: 'Nombre',
                              prefixIcon: Icon(Icons.person_outline_rounded),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (!_awaitingEmailVerification) ...[
                        TextField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          autocorrect: false,
                          autofillHints: const [AutofillHints.email],
                          decoration: const InputDecoration(
                            labelText: 'Correo',
                            prefixIcon: Icon(Icons.mail_outline_rounded),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _password,
                          obscureText: _obscure,
                          onSubmitted: (_) => _loading ? null : _submit(),
                          autofillHints: [
                            _register
                                ? AutofillHints.newPassword
                                : AutofillHints.password
                          ],
                          decoration: InputDecoration(
                            labelText: 'Contraseña',
                            prefixIcon: const Icon(Icons.lock_outline_rounded),
                            suffixIcon: IconButton(
                              tooltip: _obscure
                                  ? 'Mostrar contraseña'
                                  : 'Ocultar contraseña',
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                              icon: Icon(
                                _obscure
                                    ? Icons.visibility_rounded
                                    : Icons.visibility_off_rounded,
                              ),
                            ),
                          ),
                        ),
                        ],
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style:
                                const TextStyle(color: Colors.redAccent),
                          ),
                        ],
                        const SizedBox(height: 18),
                        FilledButton(
                          onPressed: _loading ? null : (_awaitingEmailVerification ? _confirmRegistration : _submit),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: _loading
                                ? const SizedBox.square(
                                    dimension: 22,
                                    child: PotvLoadingFlag(width: 44),
                                  )
                                : Text(_awaitingEmailVerification ? 'Verificar correo' : (_register ? 'Crear cuenta' : 'Entrar')),
                          ),
                        ),
                        if (_awaitingEmailVerification)
                          TextButton(onPressed: _loading ? null : _resendRegistration,
                            child: const Text('Reenviar código')),
                        if (!_register && !_awaitingEmailVerification)
                          TextButton(
                            onPressed: _loading ? null : _recover,
                            child: const Text('Olvidé mi contraseña'),
                          ),
                        const Divider(height: 28),
                        TextButton(
                          onPressed: _loading
                              ? null
                              : () => setState(() {
                                    if (_awaitingEmailVerification) {
                                      _awaitingEmailVerification = false;
                                    } else {
                                      _register = !_register;
                                    }
                                    _error = null;
                                  }),
                          child: Text(
                            _awaitingEmailVerification
                                ? 'Corregir correo o contraseña'
                                : (_register ? 'Ya tengo una cuenta' : 'Crear una cuenta'),
                          ),
                        ),
                      ],
                    ),
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
