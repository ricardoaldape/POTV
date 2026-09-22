import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/local/resolver_pack_bundle.dart';
import '../../data/addons/stremio_addon_client.dart';
import '../../data/addons/stremio_addon_repository.dart';
import '../../data/resolution/resolver_status.dart';
import '../../data/sources/http_source_repository.dart';
import '../../domain/models/http_source_config.dart';
import '../../domain/models/stremio_addon_config.dart';

class SourcesScreen extends ConsumerWidget {
  const SourcesScreen({super.key});

  Future<void> _addSource(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final name = TextEditingController();
    final endpoint = TextEditingController();

    final result = await showDialog<({String name, String endpoint})>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Añadir fuente POTV'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Nombre',
                  hintText: 'Mi fuente',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: endpoint,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'Endpoint POTV',
                  hintText: 'https://servidor.example/api',
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
          FilledButton(
            onPressed: () => Navigator.of(context).pop(
              (
                name: name.text.trim(),
                endpoint: endpoint.text.trim(),
              ),
            ),
            child: const Text('Añadir'),
          ),
        ],
      ),
    );

    name.dispose();
    endpoint.dispose();

    if (result == null ||
        result.name.isEmpty ||
        result.endpoint.isEmpty) {
      return;
    }

    final uri = Uri.tryParse(result.endpoint);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Endpoint HTTP/HTTPS inválido.')),
      );
      return;
    }

    await ref.read(httpSourceRepositoryProvider).add(
          name: result.name,
          endpoint: uri,
        );
    ref.invalidate(httpSourcesProvider);
    ref.invalidate(resolverStatusProvider);
  }

  Future<void> _addStremioAddon(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final controller = TextEditingController();

    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Añadir addon Stremio / Nuvio'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Pega la URL del addon o de su manifest.json. POTV la guarda únicamente en este dispositivo.',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'URL del addon',
                  hintText: 'https://addon.example/manifest.json',
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
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Comprobar y añadir'),
          ),
        ],
      ),
    );

    controller.dispose();
    if (value == null || value.isEmpty) return;

    final uri = Uri.tryParse(value);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('URL HTTP/HTTPS inválida.')),
      );
      return;
    }

    try {
      final manifest = await ref.read(stremioAddonClientProvider).inspect(uri);
      if (!manifest.supportsStreams) {
        throw const FormatException(
          'El addon no declara soporte para streams.',
        );
      }

      await ref.read(stremioAddonRepositoryProvider).add(
            name: manifest.name,
            manifestUri: manifest.manifestUri,
          );
      ref.invalidate(stremioAddonsProvider);
      ref.invalidate(resolverStatusProvider);

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${manifest.name} · v${manifest.version} añadido a POTV.',
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No pudimos añadir el addon: $error'),
        ),
      );
    }
  }

  Future<void> _toggleHttp(
    WidgetRef ref,
    HttpSourceConfig source,
    bool enabled,
  ) async {
    await ref.read(httpSourceRepositoryProvider).update(
          source.copyWith(enabled: enabled),
        );
    ref.invalidate(httpSourcesProvider);
    ref.invalidate(resolverStatusProvider);
  }

  Future<void> _removeHttp(
    WidgetRef ref,
    String id,
  ) async {
    await ref.read(httpSourceRepositoryProvider).remove(id);
    ref.invalidate(httpSourcesProvider);
    ref.invalidate(resolverStatusProvider);
  }

  Future<void> _toggleAddon(
    WidgetRef ref,
    StremioAddonConfig addon,
    bool enabled,
  ) async {
    await ref.read(stremioAddonRepositoryProvider).update(
          addon.copyWith(enabled: enabled),
        );
    ref.invalidate(stremioAddonsProvider);
    ref.invalidate(resolverStatusProvider);
  }

  Future<void> _removeAddon(
    WidgetRef ref,
    String id,
  ) async {
    await ref.read(stremioAddonRepositoryProvider).remove(id);
    ref.invalidate(stremioAddonsProvider);
    ref.invalidate(resolverStatusProvider);
  }

  Future<void> _exportResolverPack(
    BuildContext context,
  ) async {
    final raw = await ResolverPackBundle.exportJson();
    await Clipboard.setData(ClipboardData(text: raw));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Resolver Pack copiado al portapapeles.'),
      ),
    );
  }

  Future<void> _importResolverPack(
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
      final result = await ResolverPackBundle.importJson(raw);
      ref.invalidate(httpSourcesProvider);
    ref.invalidate(resolverStatusProvider);
      ref.invalidate(stremioAddonsProvider);
      ref.invalidate(resolverStatusProvider);
      ref.invalidate(resolverStatusProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Resolver Pack importado: ${result.httpSourcesAdded} fuentes y ${result.addonsAdded} addons nuevos.',
          ),
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
    final httpSources = ref.watch(httpSourcesProvider);
    final addons = ref.watch(stremioAddonsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fuentes y addons'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Añadir',
            onSelected: (value) {
              if (value == 'potv') {
                _addSource(context, ref);
              } else if (value == 'stremio') {
                _addStremioAddon(context, ref);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'potv',
                child: ListTile(
                  leading: Icon(Icons.hub_outlined),
                  title: Text('Fuente POTV'),
                ),
              ),
              PopupMenuItem(
                value: 'stremio',
                child: ListTile(
                  leading: Icon(Icons.extension_rounded),
                  title: Text('Addon Stremio / Nuvio'),
                ),
              ),
            ],
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 36),
        children: [
          const _InfoCard(),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Resolver Pack',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Importa o comparte un paquete de endpoints POTV y addons compatibles sin recompilar la app.',
                    style: TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _importResolverPack(context, ref),
                        icon: const Icon(Icons.content_paste_rounded),
                        label: const Text('Importar pack'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _exportResolverPack(context),
                        icon: const Icon(Icons.copy_all_rounded),
                        label: const Text('Copiar pack'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
          _SectionHeader(
            icon: Icons.extension_rounded,
            title: 'Stremio / Nuvio',
            subtitle:
                'POTV consulta el addon directamente desde tu dispositivo.',
            onAdd: () => _addStremioAddon(context, ref),
          ),
          const SizedBox(height: 10),
          addons.when(
            loading: () => const LinearProgressIndicator(minHeight: 2),
            error: (error, stack) => _ErrorCard(error: error),
            data: (items) => items.isEmpty
                ? const _EmptySection(
                    text: 'No hay addons configurados.',
                  )
                : Column(
                    children: [
                      for (final addon in items)
                        _AddonTile(
                          addon: addon,
                          onToggle: (value) =>
                              _toggleAddon(ref, addon, value),
                          onRemove: () => _removeAddon(ref, addon.id),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 28),
          _SectionHeader(
            icon: Icons.hub_outlined,
            title: 'Fuentes POTV',
            subtitle:
                'Endpoints compatibles con el protocolo nativo de fuentes POTV.',
            onAdd: () => _addSource(context, ref),
          ),
          const SizedBox(height: 10),
          httpSources.when(
            loading: () => const LinearProgressIndicator(minHeight: 2),
            error: (error, stack) => _ErrorCard(error: error),
            data: (items) => items.isEmpty
                ? const _EmptySection(
                    text: 'No hay fuentes POTV configuradas.',
                  )
                : Column(
                    children: [
                      for (final source in items)
                        _HttpSourceTile(
                          source: source,
                          onToggle: (value) =>
                              _toggleHttp(ref, source, value),
                          onRemove: () => _removeHttp(ref, source.id),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.shield_outlined),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Las URLs, respuestas y servidores de estas integraciones permanecen en el dispositivo. POTV no los sincroniza con su servidor.',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onAdd;

  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                subtitle,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Añadir',
          onPressed: onAdd,
          icon: const Icon(Icons.add_circle_outline_rounded),
        ),
      ],
    );
  }
}

class _AddonTile extends StatelessWidget {
  final StremioAddonConfig addon;
  final ValueChanged<bool> onToggle;
  final VoidCallback onRemove;

  const _AddonTile({
    required this.addon,
    required this.onToggle,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.extension_rounded),
        title: Text(addon.name),
        subtitle: Text(
          addon.manifestUri.toString(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              value: addon.enabled,
              onChanged: onToggle,
            ),
            IconButton(
              tooltip: 'Eliminar',
              onPressed: onRemove,
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
      ),
    );
  }
}

class _HttpSourceTile extends StatelessWidget {
  final HttpSourceConfig source;
  final ValueChanged<bool> onToggle;
  final VoidCallback onRemove;

  const _HttpSourceTile({
    required this.source,
    required this.onToggle,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.hub_outlined),
        title: Text(source.name),
        subtitle: Text(
          source.endpoint.toString(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              value: source.enabled,
              onChanged: onToggle,
            ),
            IconButton(
              tooltip: 'Eliminar',
              onPressed: onRemove,
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptySection extends StatelessWidget {
  final String text;

  const _EmptySection({required this.text});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          text,
          style: const TextStyle(color: Colors.white60),
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final Object error;

  const _ErrorCard({required this.error});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'No pudimos cargar esta sección. $error',
          style: const TextStyle(color: Colors.redAccent),
        ),
      ),
    );
  }
}
