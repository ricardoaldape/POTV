import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/sources/http_source_repository.dart';
import '../../domain/models/http_source_config.dart';

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
        title: const Text('Añadir fuente HTTP'),
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
  }

  Future<void> _toggle(
    WidgetRef ref,
    HttpSourceConfig source,
    bool enabled,
  ) async {
    await ref.read(httpSourceRepositoryProvider).update(
          source.copyWith(enabled: enabled),
        );
    ref.invalidate(httpSourcesProvider);
  }

  Future<void> _remove(
    WidgetRef ref,
    String id,
  ) async {
    await ref.read(httpSourceRepositoryProvider).remove(id);
    ref.invalidate(httpSourcesProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sources = ref.watch(httpSourcesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fuentes'),
        actions: [
          IconButton(
            tooltip: 'Añadir fuente',
            onPressed: () => _addSource(context, ref),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: sources.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Text(error.toString()),
        ),
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.hub_outlined, size: 72),
                      const SizedBox(height: 18),
                      const Text(
                        'No hay fuentes configuradas',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Las fuentes se guardan únicamente en este dispositivo. POTV consulta directamente el endpoint configurado.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white60),
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: () => _addSource(context, ref),
                        icon: const Icon(Icons.add),
                        label: const Text('Añadir fuente'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final source = items[index];
              return ListTile(
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
                      onChanged: (value) => _toggle(ref, source, value),
                    ),
                    IconButton(
                      tooltip: 'Eliminar',
                      onPressed: () => _remove(ref, source.id),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
