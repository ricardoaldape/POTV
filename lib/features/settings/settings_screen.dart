import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/local/local_config_bundle.dart';
import '../../data/live_tv/live_tv_repository.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _copyConfig(BuildContext context) async {
    final raw = await LocalConfigBundle.exportJson();
    await Clipboard.setData(ClipboardData(text: raw));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Configuración local copiada. Trátala como privada.',
        ),
      ),
    );
  }

  Future<void> _importConfig(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final raw = data?.text?.trim();
    if (raw == null || raw.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El portapapeles está vacío.')),
      );
      return;
    }

    try {
      await LocalConfigBundle.importJson(raw);
      ref.invalidate(liveChannelsProvider);
      ref.invalidate(epgProgramsProvider);

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Configuración local importada.'),
        ),
      );
    } on FormatException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: ListView(
        children: [
          const ListTile(
            leading: Icon(Icons.shield_outlined),
            title: Text('Privacidad local-first'),
            subtitle: Text(
              'Fuentes, historial y credenciales permanecen en el dispositivo.',
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.content_copy),
            title: const Text('Copiar configuración local'),
            subtitle: const Text(
              'Crea un paquete POTV para transferirlo manualmente a otro dispositivo.',
            ),
            onTap: () => _copyConfig(context),
          ),
          ListTile(
            leading: const Icon(Icons.content_paste),
            title: const Text('Importar configuración local'),
            subtitle: const Text(
              'Lee un paquete POTV desde el portapapeles de este dispositivo.',
            ),
            onTap: () => _importConfig(context, ref),
          ),
          const ListTile(
            leading: Icon(Icons.devices),
            title: Text('Sincronizar dispositivos'),
            subtitle: Text(
              'Siguiente etapa: transferencia local cifrada móvil ↔ Android TV.',
            ),
          ),
          const Divider(),
          const ListTile(
            leading: Icon(Icons.extension),
            title: Text('Addons'),
            subtitle: Text(
              'Stremio, Nuvio y Kodi se implementarán después de Live TV y Sports Hub.',
            ),
          ),
        ],
      ),
    );
  }
}
