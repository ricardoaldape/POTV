import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/addons/stremio_addon_repository.dart';
import '../../data/addons/private_addon_link.dart';
import '../../data/live_tv/live_tv_repository.dart';
import '../../data/plugins/nuvio_plugin_repository.dart';
import '../../data/resolution/resolver_status.dart';
import '../../data/resolution/source_aggregator.dart';
import '../../data/sources/universal_source_installer.dart';

class VodSourceSetupScreen extends ConsumerStatefulWidget {
  const VodSourceSetupScreen({super.key});

  @override
  ConsumerState<VodSourceSetupScreen> createState() => _VodSourceSetupScreenState();
}

class _VodSourceSetupScreenState extends ConsumerState<VodSourceSetupScreen> {
  final controller = TextEditingController();
  bool busy = false;
  String? error;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) return;
    controller.text = text;
    controller.selection = TextSelection.collapsed(offset: controller.text.length);
    if (mounted) setState(() {});
  }

  Future<void> _connectPrivateAddon() async {
    if (busy) return;
    final privateToken = TextEditingController();
    var visible = false;
    final input = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Conectar PenguPlay'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 450),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Introduce tu token personal o pega tu enlace del addon. '
                  'Sólo es necesario hacerlo una vez en este dispositivo.',
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('private-addon-token'),
                  controller: privateToken,
                  obscureText: !visible,
                  enableSuggestions: false,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: 'Código privado',
                    suffixIcon: IconButton(
                      tooltip: visible ? 'Ocultar código' : 'Mostrar código',
                      onPressed: () => update(() => visible = !visible),
                      icon: Icon(visible
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, privateToken.text),
              child: const Text('Conectar'),
            ),
          ],
        ),
      ),
    );
    privateToken.clear();
    privateToken.dispose();
    if (input == null || !mounted) return;
    try {
      final manifest = PrivateAddonLink.penguPlay(input);
      // The credential never appears in UI, errors or GitHub and only
      // persists in the encrypted addon secret store on this device.
      setState(() {
        busy = true;
        error = null;
      });
      final result = await ref.read(universalSourceInstallerProvider)
          .install(manifest.toString());
      ref.invalidate(stremioAddonsProvider);
      ref.invalidate(resolverStatusProvider);
      ref.read(sourceAggregatorProvider).clearCache();
      if (!mounted) return;
      if (!result.active) {
        setState(() { busy = false; error = 'No se pudo conectar la fuente.'; });
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fuente privada conectada. Ya puedes reproducir.')),
      );
      context.pop(true);
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          error = 'No se pudo validar el acceso privado. Revisa el token.';
        });
      }
    }
  }

  Future<void> _connect() async {
    final value = controller.text.trim();
    if (value.isEmpty || busy) return;

    setState(() {
      busy = true;
      error = null;
    });

    try {
      final result = await ref.read(universalSourceInstallerProvider).install(value);
      ref.invalidate(stremioAddonsProvider);
      ref.invalidate(nuvioPluginsProvider);
      ref.invalidate(resolverStatusProvider);
      ref.invalidate(liveChannelsProvider);
      ref.read(sourceAggregatorProvider).clearCache();

      if (!mounted) return;
      if (!result.active) {
        setState(() {
          busy = false;
          error = result.message;
        });
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message)),
      );
      context.pop(true);
    } on FormatException catch (e) {
      if (!mounted) return;
      setState(() {
        busy = false;
        error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        busy = false;
        error = 'No se pudo conectar la fuente. Verifica la dirección y vuelve a intentar.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configurar VOD'),
        leading: IconButton(
          onPressed: busy ? null : () => context.pop(false),
          icon: const Icon(Icons.close_rounded),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.play_circle_fill_rounded, size: 52),
                      const SizedBox(height: 18),
                      const Text(
                        'Conecta tu fuente una sola vez',
                        style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'POTV la guardará en este dispositivo. Después sólo eliges una película, serie o anime y pulsas Play; POTV consulta las fuentes automáticamente.',
                        style: TextStyle(color: Colors.white70, height: 1.45),
                      ),
                      const SizedBox(height: 22),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          key: const ValueKey('connect-private-addon'),
                          onPressed: busy ? null : _connectPrivateAddon,
                          icon: const Icon(Icons.lock_rounded),
                          label: const Text('Conectar PenguPlay con código privado'),
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'También puedes usar otra fuente compatible:',
                        style: TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: controller,
                        autofocus: false,
                        obscureText: true,
                        enableSuggestions: false,
                        autocorrect: false,
                        keyboardType: TextInputType.url,
                        enabled: !busy,
                        onSubmitted: (_) => _connect(),
                        decoration: InputDecoration(
                          labelText: 'URL de la fuente',
                          hintText: 'https://…/manifest.json',
                          suffixIcon: IconButton(
                            tooltip: 'Pegar',
                            onPressed: busy ? null : _paste,
                            icon: const Icon(Icons.content_paste_rounded),
                          ),
                        ),
                      ),
                      if (error != null) ...[
                        const SizedBox(height: 12),
                        Text(error!, style: const TextStyle(color: Colors.redAccent)),
                      ],
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: busy ? null : _connect,
                          icon: busy
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.link_rounded),
                          label: Text(busy ? 'Conectando…' : 'Conectar fuente'),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          onPressed: busy ? null : () => context.pop(false),
                          child: const Text('Continuar sólo con TV/deportes'),
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
    );
  }
}
