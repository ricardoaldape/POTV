import 'package:flutter/material.dart';
import '../../data/services/supabase_auth_service.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key, this.authService, this.onRegistered});

  final SupabaseAuthService? authService;
  final VoidCallback? onRegistered;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  String? _error;

  SupabaseAuthService get _auth => widget.authService ?? SupabaseAuthService();

  @override
  void dispose() {
    _email.dispose(); _username.dispose(); _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });
    try {
      await _auth.signUp(_email.text, _password.text, _username.text);
      if (!mounted) return;
      widget.onRegistered?.call();
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = 'No se pudo crear la cuenta. Revisa los datos e inténtalo de nuevo.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Crear cuenta')),
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _username,
                    decoration: const InputDecoration(labelText: 'Nombre de usuario'),
                    validator: (v) => v == null || v.trim().length < 2 ? 'Ingresa un nombre de usuario' : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(labelText: 'Email'),
                    validator: (v) => v == null || !v.contains('@') ? 'Ingresa un email válido' : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _password,
                    obscureText: true,
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: const InputDecoration(labelText: 'Contraseña'),
                    validator: (v) => v == null || v.length < 6 ? 'Usa al menos 6 caracteres' : null,
                  ),
                  if (_error != null) Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _loading ? null : _submit,
                    child: _loading ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Registrarme'),
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
