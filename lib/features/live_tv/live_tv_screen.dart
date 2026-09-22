import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/live_tv/live_tv_repository.dart';
import '../../domain/models/epg_program.dart';
import '../../domain/models/live_channel.dart';

class LiveTvScreen extends ConsumerStatefulWidget {
  const LiveTvScreen({super.key});

  @override
  ConsumerState<LiveTvScreen> createState() => _LiveTvScreenState();
}

class _LiveTvScreenState extends ConsumerState<LiveTvScreen> {
  String searchQuery = '';
  String? selectedGroup;

  Future<void> _addSource() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Añadir TV'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'URL M3U',
            hintText: 'https://proveedor.example/lista.m3u',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => context.pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => context.pop(controller.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (value != null && value.isNotEmpty) {
      await ref.read(liveChannelsProvider.notifier).setSource(value);
      if (mounted) setState(() => selectedGroup = null);
    }
  }

  Future<void> _importPlaylistFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['m3u', 'm3u8', 'txt'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final bytes = result.files.single.bytes;
    if (bytes == null || bytes.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No pudimos leer el archivo.')),
      );
      return;
    }

    final raw = utf8.decode(bytes, allowMalformed: true);
    if (!raw.contains('#EXTM3U')) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El archivo no parece una lista M3U.')),
      );
      return;
    }

    await ref.read(liveChannelsProvider.notifier).setLocalPlaylist(raw);
    if (mounted) setState(() => selectedGroup = null);
  }

  Future<void> _addEpgSource() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Añadir guía EPG'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'URL XMLTV',
            hintText: 'https://proveedor.example/guide.xml',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => context.pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => context.pop(controller.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (value != null && value.isNotEmpty) {
      await ref.read(epgProgramsProvider.notifier).setSource(value);
    }
  }

  EpgProgram? _currentProgram(
    LiveChannel channel,
    List<EpgProgram> programs,
  ) {
    final now = DateTime.now();
    for (final program in programs) {
      final matches = program.channelId == channel.epgId ||
          program.channelId == channel.name;
      if (matches && program.isOnAir(now)) return program;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final channelsState = ref.watch(liveChannelsProvider);
    final epgState = ref.watch(epgProgramsProvider);
    final programs = epgState.asData?.value ?? const <EpgProgram>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live TV'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: () {
              ref.read(liveChannelsProvider.notifier).refresh();
              ref.read(epgProgramsProvider.notifier).refresh();
            },
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Importar archivo M3U',
            onPressed: _importPlaylistFile,
            icon: const Icon(Icons.file_open_outlined),
          ),
          IconButton(
            tooltip: 'Añadir guía EPG',
            onPressed: _addEpgSource,
            icon: const Icon(Icons.calendar_month),
          ),
          IconButton(
            tooltip: 'Añadir lista',
            onPressed: _addSource,
            icon: const Icon(Icons.add_link),
          ),
        ],
      ),
      body: channelsState.when(
        data: (items) {
          if (items.isEmpty) {
            return _EmptyTv(onAdd: _addSource);
          }

          final groups = items
              .map((channel) => channel.group?.trim())
              .whereType<String>()
              .where((group) => group.isNotEmpty)
              .toSet()
              .toList()
            ..sort();

          final query = searchQuery.trim().toLowerCase();
          final filtered = items.where((channel) {
            final groupMatches =
                selectedGroup == null || channel.group == selectedGroup;
            if (!groupMatches) return false;
            if (query.isEmpty) return true;

            final program = _currentProgram(channel, programs);
            final haystack = [
              channel.name,
              channel.group ?? '',
              program?.title ?? '',
            ].join(' ').toLowerCase();
            return haystack.contains(query);
          }).toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
                child: TextField(
                  onChanged: (value) => setState(() => searchQuery = value),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Buscar canal o programa',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              if (groups.isNotEmpty)
                SizedBox(
                  height: 48,
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    scrollDirection: Axis.horizontal,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: const Text('Todos'),
                          selected: selectedGroup == null,
                          onSelected: (_) {
                            setState(() => selectedGroup = null);
                          },
                        ),
                      ),
                      for (final group in groups)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(group),
                            selected: selectedGroup == group,
                            onSelected: (_) {
                              setState(() => selectedGroup = group);
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              Expanded(
                child: filtered.isEmpty
                    ? const Center(
                        child: Text('No encontramos canales con ese filtro.'),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.all(18),
                        gridDelegate:
                            SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent:
                              MediaQuery.sizeOf(context).width >= 900
                                  ? 300
                                  : 230,
                          mainAxisExtent: 128,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final channel = filtered[index];
                          final program =
                              _currentProgram(channel, programs);

                          return Card(
                            child: InkWell(
                              onTap: () => context.push(
                                '/player',
                                extra: channel.stream,
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 24,
                                      backgroundImage: channel.logo == null
                                          ? null
                                          : NetworkImage(
                                              channel.logo.toString(),
                                            ),
                                      child: channel.logo == null
                                          ? const Icon(Icons.live_tv)
                                          : null,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            channel.name,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          if (channel.group != null)
                                            Text(
                                              channel.group!,
                                              maxLines: 1,
                                              overflow:
                                                  TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Colors.white54,
                                              ),
                                            ),
                                          if (program != null)
                                            Text(
                                              program.title,
                                              maxLines: 1,
                                              overflow:
                                                  TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Colors.white70,
                                                fontSize: 12,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
        error: (error, stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'No pudimos cargar la lista.\n$error',
              textAlign: TextAlign.center,
            ),
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _EmptyTv extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyTv({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.live_tv_rounded, size: 72),
              const SizedBox(height: 20),
              const Text(
                'Añade tu televisión',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'POTV guarda la configuración en este dispositivo y consulta la fuente directamente. La lista no se envía a nuestros servidores.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add),
                label: const Text('Añadir lista M3U'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
