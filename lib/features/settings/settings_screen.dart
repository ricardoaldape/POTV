import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/local/local_config_bundle.dart';
import '../../data/addons/stremio_addon_repository.dart';
import '../../data/addons/stremio_source_resolver.dart';
import '../../data/bootstrap/default_manifest_bootstrap.dart';
import '../../data/debug/debug_log_provider.dart';
import '../../data/resolution/resolver_status.dart';
import '../../data/live_tv/built_in_live_sources.dart';
import '../../data/live_tv/live_tv_repository.dart';
import '../../data/sources/http_source_repository.dart';
import '../../domain/models/playback_session.dart';
import '../../domain/models/stream_candidate.dart';
import '../../domain/resolution/provider_resolver.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  static final Uri _telegramUri = Uri.parse('https://t.me/potv_oficial');

  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _diagnosticRunning = false;
  String _diagnosticText = '';

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

  Future<void> _runReproductionDiagnostic() async {
    setState(() {
      _diagnosticRunning = true;
      _diagnosticText = 'Ejecutando diagnóstico de reproducción…';
    });

    final report = StringBuffer();
    report.writeln('Diagnóstico de reproducción');
    report.writeln('---');

    try {
      final resolver = ref.read(stremioSourceResolverProvider);
      final addonReport = await resolver.debugAddonReport(
        mediaType: 'movie',
        mediaId: 'tt0133093',
        externalId: 'tt0133093',
        title: 'The Matrix',
      );
      report.writelnAll(addonReport, '\n');

      final aggregator = ref.read(sourceAggregatorProvider);
      final result = await aggregator.resolve(
        const ProviderResolveRequest(
          mediaType: 'movie',
          mediaId: 'tt0133093',
          externalId: 'tt0133093',
          title: 'The Matrix',
        ),
      );

      report.writeln('---');
      report.writeln('Resultado agregado: ${result.candidates.length} fuentes totales');
      report.writeln(
        'Primeras 3 URLs: ${result.candidates.take(3).map((candidate) => candidate.uri.toString()).join(' | ') == '' ? 'ninguna' : result.candidates.take(3).map((candidate) => candidate.uri.toString()).join(' | ')}',
      );
    } catch (error, stack) {
      report.writeln('ERROR DEL RESOLVER');
      report.writeln(error.toString());
      report.writeln(stack.toString());
    }

    if (!mounted) return;
    setState(() {
      _diagnosticRunning = false;
      _diagnosticText = report.toString();
    });
  }

  @override
  Widget build(BuildContext context) {
    final tvState = ref.watch(liveChannelsProvider);
    final sportsState = ref.watch(builtInSportsChannelsProvider);
    final vodSourcesState = ref.watch(httpSourcesProvider);
    final addonState = ref.watch(stremioAddonsProvider);
    final resolverStatus = ref.watch(resolverStatusProvider);
    final defaultManifestResult = ref.watch(defaultManifestBootstrapResultProvider);
    final debugLogs = ref.watch(debugLogProvider);
    final recentLogs = debugLogs.length > 10
        ? debugLogs.sublist(debugLogs.length - 10)
        : debugLogs;

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
                    const SizedBox(height: 8),
                    _StatusRow(
                      icon: Icons.account_tree_outlined,
                      label: 'Fuentes VOD externas',
                      value: resolverStatus.when(
                        data: (status) => status.externalRoutes.toString(),
                        loading: () => '…',
                        error: (error, stack) => 'Error',
                      ),
                    ),
                    resolverStatus.when(
                      data: (status) => Padding(
                        padding: const EdgeInsets.only(top: 4, left: 30),
                        child: Text(
                          'Externas: build ${status.buildResolvers} · locales ${status.localHttpSources} · addons ${status.addons} · plugins ${status.nuvioPlugins}. Fallback público: ${status.builtInResolvers}.',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      loading: () => const SizedBox.shrink(),
                      error: (error, stack) => const SizedBox.shrink(),
                    ),
                    if (defaultManifestResult != null) ...[
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.only(left: 30),
                        child: Text(
                          'Manifiestos al inicio: intentados ${defaultManifestResult.attempted} · instalados ${defaultManifestResult.installed} · fallidos ${defaultManifestResult.failures.length}',
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (defaultManifestResult.failures.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6, left: 30),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final entry in defaultManifestResult.failures.entries) ...[
                                SelectableText(
                                  entry.key,
                                  style: const TextStyle(
                                    color: Colors.redAccent,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                SelectableText(
                                  entry.value,
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 10,
                                  ),
                                ),
                                const SizedBox(height: 8),
                              ],
                            ],
                          ),
                        ),
                    ],
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _diagnosticRunning ? null : _runReproductionDiagnostic,
                            icon: const Icon(Icons.bug_report_rounded),
                            label: const Text('Diagnóstico de reproducción'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (_diagnosticText.isNotEmpty) ...[
                      Container(
                        constraints: const BoxConstraints(maxHeight: 220),
                        decoration: BoxDecoration(
                          color: Colors.black12,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.all(10),
                        child: SingleChildScrollView(
                          child: SelectableText(
                            _diagnosticText,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          TextButton.icon(
                            onPressed: () async {
                              await Clipboard.setData(
                                ClipboardData(text: _diagnosticText),
                              );
                            },
                            icon: const Icon(Icons.copy_all_rounded),
                            label: const Text('Copiar resultado'),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 14),
                    const Text(
                      'Últimos logs de reproducción',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 220),
                      decoration: BoxDecoration(
                        color: Colors.black12,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.all(8),
                      child: recentLogs.isEmpty
                          ? const Text(
                              'No hay logs aún.',
                              style: TextStyle(color: Colors.white54),
                            )
                          : ListView.separated(
                              itemCount: recentLogs.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 4),
                              itemBuilder: (context, index) {
                                final message = recentLogs[index];
                                return SelectableText(
                                  message,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 10,
                                  ),
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        TextButton.icon(
                          onPressed: () {
                            ref.read(debugLogProvider.notifier).clear();
                          },
                          icon: const Icon(Icons.delete_outline_rounded),
                          label: const Text('Limpiar logs'),
                        ),
                        const SizedBox(width: 8),
                        TextButton.icon(
                          onPressed: () async {
                            final all = ref.read(debugLogProvider);
                            await Clipboard.setData(
                              ClipboardData(text: all.join('\n')),
                            );
                          },
                          icon: const Icon(Icons.copy_all_rounded),
                          label: const Text('Copiar logs'),
                        ),
                      ],
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
