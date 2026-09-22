import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/addons/stremio_addon_client.dart';
import '../../data/addons/stremio_addon_repository.dart';
import '../../data/live_tv/live_tv_repository.dart';
import '../../data/plugins/nuvio_plugin_repository.dart';
import '../../data/resolution/resolver_status.dart';
import '../../data/sources/http_source_repository.dart';
import '../../data/sources/universal_source_installer.dart';
import '../../domain/models/http_source_config.dart';
import '../../domain/models/nuvio_plugin_config.dart';
import '../../domain/models/stremio_addon_config.dart';

class SourcesScreen extends ConsumerWidget {
  const SourcesScreen({super.key});

  Future<void> _addUniversal(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Agregar fuente'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Pega una URL. POTV intentará reconocerla automáticamente.',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'URL',
                  hintText: 'https://ejemplo.com/manifest.json',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Agregar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value.isEmpty) return;

    try {
      final result = await ref.read(universalSourceInstallerProvider).install(value);
      ref.invalidate(stremioAddonsProvider);
      ref.invalidate(nuvioPluginsProvider);
      ref.invalidate(resolverStatusProvider);
      ref.invalidate(liveChannelsProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          duration: const Duration(seconds: 4),
        ),
      );
    } on FormatException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No pudimos agregar la fuente: $error')),
      );
    }
  }

  Future<void> _addSource(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    final endpoint = TextEditingController();
    final result = await showDialog<({String name, String endpoint})>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Agregar endpoint POTV'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Nombre')),
              const SizedBox(height: 12),
              TextField(
                controller: endpoint,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(labelText: 'Endpoint'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.of(context).pop((name: name.text.trim(), endpoint: endpoint.text.trim())),
            child: const Text('Agregar'),
          ),
        ],
      ),
    );
    name.dispose();
    endpoint.dispose();
    if (result == null || result.name.isEmpty || result.endpoint.isEmpty) return;
    final uri = Uri.tryParse(result.endpoint);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) return;
    await ref.read(httpSourceRepositoryProvider).add(name: result.name, endpoint: uri);
    ref.invalidate(httpSourcesProvider);
    ref.invalidate(resolverStatusProvider);
  }

  Future<void> _addStremioAddon(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Agregar addon compatible'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(labelText: 'URL o manifest.json'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Agregar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value.isEmpty) return;
    final uri = Uri.tryParse(value);
    if (uri == null) return;
    final manifest = await ref.read(stremioAddonClientProvider).inspect(uri);
    await ref.read(stremioAddonRepositoryProvider).add(name: manifest.name, manifestUri: manifest.manifestUri);
    ref.invalidate(stremioAddonsProvider);
    ref.invalidate(resolverStatusProvider);
  }

  Future<void> _toggleHttp(WidgetRef ref, HttpSourceConfig source, bool enabled) async {
    await ref.read(httpSourceRepositoryProvider).update(source.copyWith(enabled: enabled));
    ref.invalidate(httpSourcesProvider);
    ref.invalidate(resolverStatusProvider);
  }

  Future<void> _removeHttp(WidgetRef ref, String id) async {
    await ref.read(httpSourceRepositoryProvider).remove(id);
    ref.invalidate(httpSourcesProvider);
    ref.invalidate(resolverStatusProvider);
  }

  Future<void> _toggleAddon(WidgetRef ref, StremioAddonConfig addon, bool enabled) async {
    await ref.read(stremioAddonRepositoryProvider).update(addon.copyWith(enabled: enabled));
    ref.invalidate(stremioAddonsProvider);
    ref.invalidate(resolverStatusProvider);
  }

  Future<void> _removeAddon(WidgetRef ref, String id) async {
    await ref.read(stremioAddonRepositoryProvider).remove(id);
    ref.invalidate(stremioAddonsProvider);
    ref.invalidate(resolverStatusProvider);
  }

  Future<void> _togglePlugin(WidgetRef ref, NuvioPluginConfig plugin, bool enabled) async {
    await ref.read(nuvioPluginRepositoryProvider).update(plugin.copyWith(enabled: enabled));
    ref.invalidate(nuvioPluginsProvider);
    ref.invalidate(resolverStatusProvider);
  }

  Future<void> _removePlugin(WidgetRef ref, String id) async {
    await ref.read(nuvioPluginRepositoryProvider).remove(id);
    ref.invalidate(nuvioPluginsProvider);
    ref.invalidate(resolverStatusProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final httpSources = ref.watch(httpSourcesProvider);
    final addons = ref.watch(stremioAddonsProvider);
    final plugins = ref.watch(nuvioPluginsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Fuentes')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 36),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Una sola entrada', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 7),
                  const Text(
                    'Pega una URL y POTV detecta si es un addon compatible, un repositorio de plugins o una lista M3U.',
                    style: TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: () => _addUniversal(context, ref),
                    icon: const Icon(Icons.add_link_rounded),
                    label: const Text('Agregar fuente'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
          const _SectionTitle(title: 'Plugins automáticos', subtitle: 'Se consultan en segundo plano al pulsar Play.'),
          const SizedBox(height: 8),
          plugins.when(
            loading: () => const LinearProgressIndicator(minHeight: 2),
            error: (error, stack) => _ErrorCard(error: error),
            data: (items) => items.isEmpty
                ? const _EmptySection(text: 'No hay plugins instalados.')
                : Column(
                    children: [
                      for (final plugin in items)
                        _PluginTile(
                          plugin: plugin,
                          onToggle: (value) => _togglePlugin(ref, plugin, value),
                          onRemove: () => _removePlugin(ref, plugin.id),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 22),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Opciones avanzadas', style: TextStyle(fontWeight: FontWeight.w800)),
            subtitle: const Text('Addons y endpoints configurados manualmente.'),
            children: [
              _SectionHeader(
                icon: Icons.extension_rounded,
                title: 'Addons compatibles',
                onAdd: () => _addStremioAddon(context, ref),
              ),
              addons.when(
                loading: () => const LinearProgressIndicator(minHeight: 2),
                error: (error, stack) => _ErrorCard(error: error),
                data: (items) => items.isEmpty
                    ? const _EmptySection(text: 'No hay addons configurados.')
                    : Column(children: [
                        for (final addon in items)
                          _AddonTile(
                            addon: addon,
                            onToggle: (value) => _toggleAddon(ref, addon, value),
                            onRemove: () => _removeAddon(ref, addon.id),
                          ),
                      ]),
              ),
              const SizedBox(height: 16),
              _SectionHeader(
                icon: Icons.hub_outlined,
                title: 'Endpoints POTV',
                onAdd: () => _addSource(context, ref),
              ),
              httpSources.when(
                loading: () => const LinearProgressIndicator(minHeight: 2),
                error: (error, stack) => _ErrorCard(error: error),
                data: (items) => items.isEmpty
                    ? const _EmptySection(text: 'No hay endpoints configurados.')
                    : Column(children: [
                        for (final source in items)
                          _HttpSourceTile(
                            source: source,
                            onToggle: (value) => _toggleHttp(ref, source, value),
                            onRemove: () => _removeHttp(ref, source.id),
                          ),
                      ]),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String subtitle;
  const _SectionTitle({required this.title, required this.subtitle});
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 12)),
        ],
      );
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onAdd;
  const _SectionHeader({required this.icon, required this.title, required this.onAdd});
  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        trailing: IconButton(onPressed: onAdd, icon: const Icon(Icons.add_circle_outline_rounded)),
      );
}

class _PluginTile extends StatelessWidget {
  final NuvioPluginConfig plugin;
  final ValueChanged<bool> onToggle;
  final VoidCallback onRemove;
  const _PluginTile({required this.plugin, required this.onToggle, required this.onRemove});
  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          leading: const Icon(Icons.bolt_rounded),
          title: Text(plugin.name),
          subtitle: Text('${plugin.repositoryName} · ${plugin.supportedMediaTypes.join(', ')}', maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            Switch(value: plugin.enabled, onChanged: onToggle),
            IconButton(onPressed: onRemove, icon: const Icon(Icons.delete_outline)),
          ]),
        ),
      );
}

class _AddonTile extends StatelessWidget {
  final StremioAddonConfig addon;
  final ValueChanged<bool> onToggle;
  final VoidCallback onRemove;
  const _AddonTile({required this.addon, required this.onToggle, required this.onRemove});
  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          leading: const Icon(Icons.extension_rounded),
          title: Text(addon.name),
          subtitle: Text(addon.manifestUri.toString(), maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            Switch(value: addon.enabled, onChanged: onToggle),
            IconButton(onPressed: onRemove, icon: const Icon(Icons.delete_outline)),
          ]),
        ),
      );
}

class _HttpSourceTile extends StatelessWidget {
  final HttpSourceConfig source;
  final ValueChanged<bool> onToggle;
  final VoidCallback onRemove;
  const _HttpSourceTile({required this.source, required this.onToggle, required this.onRemove});
  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          leading: const Icon(Icons.hub_outlined),
          title: Text(source.name),
          subtitle: Text(source.endpoint.toString(), maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            Switch(value: source.enabled, onChanged: onToggle),
            IconButton(onPressed: onRemove, icon: const Icon(Icons.delete_outline)),
          ]),
        ),
      );
}

class _EmptySection extends StatelessWidget {
  final String text;
  const _EmptySection({required this.text});
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(text, style: const TextStyle(color: Colors.white60)),
        ),
      );
}

class _ErrorCard extends StatelessWidget {
  final Object error;
  const _ErrorCard({required this.error});
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('No pudimos cargar esta sección. $error', style: const TextStyle(color: Colors.redAccent)),
        ),
      );
}
