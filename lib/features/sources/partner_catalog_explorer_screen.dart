import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/addons/partner_catalog_client.dart';
import '../../data/addons/verified_partner_catalog.dart';

/// Catalog discovery in POTV. Shows the partner's titles and artwork without
/// implying the partner supplied a playable or redistributable video stream.
class PartnerCatalogExplorerScreen extends ConsumerStatefulWidget {
  final VerifiedPartnerAddon addon;

  const PartnerCatalogExplorerScreen({super.key, required this.addon});

  @override
  ConsumerState<PartnerCatalogExplorerScreen> createState() =>
      _PartnerCatalogExplorerScreenState();
}

class _PartnerCatalogExplorerScreenState
    extends ConsumerState<PartnerCatalogExplorerScreen> {
  late final Future<List<PartnerCatalog>> catalogs;
  PartnerCatalog? selected;
  Future<List<PartnerCatalogMedia>>? items;

  @override
  void initState() {
    super.initState();
    catalogs = ref.read(partnerCatalogClientProvider).catalogs(widget.addon);
  }

  void select(PartnerCatalog value) {
    setState(() {
      selected = value;
      items = ref.read(partnerCatalogClientProvider).listings(value);
    });
  }

  void showDetails(PartnerCatalogMedia item) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              if (item.year != null) ...[
                const SizedBox(height: 5),
                Text(item.year!),
              ],
              const SizedBox(height: 12),
              Text(item.description ?? 'Sin sinopsis del proveedor.'),
              const SizedBox(height: 18),
              const Text(
                'Este catálogo contiene metadatos. La reproducción sólo '
                'está disponible si POTV dispone de una fuente autorizada.',
                style: TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.addon.name)),
      body: FutureBuilder<List<PartnerCatalog>>(
        future: catalogs,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(
              child: Text('El catálogo del proveedor no respondió.'),
            );
          }
          final values = snapshot.data ?? const <PartnerCatalog>[];
          if (values.isEmpty) {
            return const Center(
              child: Text(
                'Este complemento no ofrece catálogos navegables sin '
                'configuración adicional.',
              ),
            );
          }
          final current = selected ?? values.first;
          final loading = items ??= ref
              .read(partnerCatalogClientProvider)
              .listings(current);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Exploración de contenido · no incluye reproducción',
                      style: TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: '${current.type}:${current.id}',
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Colección',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final catalog in values)
                          DropdownMenuItem(
                            value: '${catalog.type}:${catalog.id}',
                            child: Text(
                              '${catalog.name} · ${catalog.type}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        for (final catalog in values) {
                          if ('${catalog.type}:${catalog.id}' == value) {
                            select(catalog);
                            break;
                          }
                        }
                      },
                    ),
                  ],
                ),
              ),
              Expanded(
                child: FutureBuilder<List<PartnerCatalogMedia>>(
                  key: ValueKey('${current.type}:${current.id}'),
                  future: loading,
                  builder: (context, mediaSnapshot) {
                    if (mediaSnapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (mediaSnapshot.hasError) {
                      return const Center(
                        child: Text(
                          'No se pudo consultar esta colección del proveedor.',
                        ),
                      );
                    }
                    final entries =
                        mediaSnapshot.data ?? const <PartnerCatalogMedia>[];
                    if (entries.isEmpty) {
                      return const Center(
                        child: Text('No hay títulos en esta colección.'),
                      );
                    }
                    return ListView.builder(
                      itemCount: entries.length,
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        return ListTile(
                          onTap: () => showDetails(entry),
                          leading: entry.poster == null
                              ? const Icon(Icons.movie_filter_outlined)
                              : ClipRRect(
                                  borderRadius: BorderRadius.circular(5),
                                  child: Image.network(
                                    entry.poster.toString(),
                                    width: 52,
                                    height: 70,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) =>
                                        const Icon(Icons.movie_filter_outlined),
                                  ),
                                ),
                          title: Text(
                            entry.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            [
                              if (entry.year != null) entry.year!,
                              entry.type,
                            ].join(' · '),
                          ),
                          trailing: const Icon(Icons.info_outline),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
