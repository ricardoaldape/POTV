import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/local/local_config_bundle.dart';
import '../../data/addons/stremio_addon_repository.dart';
import '../../data/live_tv/built_in_live_sources.dart';
import '../../data/live_tv/live_tv_repository.dart';
import '../../data/sources/http_source_repository.dart';
import '../../domain/models/playback_session.dart';
import '../../domain/models/stream_candidate.dart';

class SettingsScreen extends ConsumerWidget {
  static final Uri _telegramUri = Uri.parse('https://t.me/potv_oficial');

  const SettingsScreen({super.key});

  Future<void> _openTelegram(BuildContext context) async {
    final opened = await launchUrl(
      _telegramUri,
      mode: LaunchMode.externalApplication,
    );
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No pudimos abrir la comunidad de Telegram.'),
        ),
      );
    }
  }

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
      ref.invalidate(httpSourcesProvider);
      ref.invalidate(stremioAddonsProvider);

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
    final tvState = ref.watch(liveChannelsProvider);
    final sportsState = ref.watch(builtInSportsChannelsProvider);
    final vodSourcesState = ref.watch(httpSourcesProvider);
    final addonState = ref.watch(stremioAddonsProvider);

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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Estado de contenido',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _StatusRow(
                      icon: Icons.live_tv_rounded,
                      label: 'Canales TV',
                      value: _countLabel(tvState),
                    ),
                    const SizedBox(height: 8),
                    _StatusRow(
                      icon: Icons.sports_soccer_rounded,
                      label: 'Canales deportivos',
                      value: _countLabel(sportsState),
                    ),
                    const SizedBox(height: 8),
                    _StatusRow(
                      icon: Icons.hub_outlined,
                      label: 'Fuentes VOD locales',
                      value: _countLabel(vodSourcesState),
                    ),
                    const SizedBox(height: 8),
                    _StatusRow(
                      icon: Icons.extension_rounded,
                      label: 'Addons Stremio / Nuvio',
                      value: _countLabel(addonState),
                    ),
                  ],
                ),
              ),
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
          ListTile(
            leading: const Icon(Icons.play_circle_outline_rounded),
            title: const Text('Probar reproductor'),
            subtitle: const Text(
              'Abre un stream público de prueba para verificar video, controles y audio.',
            ),
            onTap: () => context.push(
              '/player',
              extra: PlaybackSession.single(
                StreamCandidate(
                  id: 'potv-demo-hls',
                  label: 'POTV Demo · HLS 1080p',
                  uri: Uri.parse(
                    'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
                  ),
                  language: 'demo',
                  quality: '1080p',
                ),
              ),
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.hub_outlined),
            title: const Text('Fuentes locales'),
            subtitle: const Text(
              'Administra endpoints POTV guardados únicamente en este dispositivo.',
            ),
            onTap: () => context.push('/sources'),
          ),
          ListTile(
            leading: const Icon(Icons.extension_rounded),
            title: const Text('Addons Stremio / Nuvio'),
            subtitle: const Text(
              'Instala addons remotos compatibles. Kodi seguirá en una etapa posterior.',
            ),
            onTap: () => context.push('/sources'),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.forum_rounded),
            title: const Text('Comunidad oficial POTV'),
            subtitle: const Text(
              'Noticias, soporte, nuevas versiones y comunidad en Telegram.',
            ),
            trailing: const Icon(Icons.open_in_new_rounded),
            onTap: () => _openTelegram(context),
          ),
        ],
      ),
    );
  }
}


String _countLabel<T>(AsyncValue<List<T>> state) {
  return state.when(
    data: (items) => items.length.toString(),
    loading: () => '…',
    error: (error, stack) => 'Error',
  );
}

class _StatusRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _StatusRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.white70),
        const SizedBox(width: 10),
        Expanded(child: Text(label)),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}
