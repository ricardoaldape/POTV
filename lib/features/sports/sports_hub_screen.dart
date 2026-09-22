import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../data/live_tv/live_tv_repository.dart';
import '../../data/sports/sports_repository.dart';
import '../../domain/models/epg_program.dart';
import '../../domain/models/live_channel.dart';
import '../../domain/models/sports_event.dart';
import '../../domain/services/sports_channel_resolver.dart';

const _sports = <({String label, String api, IconData icon})>[
  (label: 'Fútbol', api: 'Soccer', icon: Icons.sports_soccer),
  (label: 'Basket', api: 'Basketball', icon: Icons.sports_basketball),
  (
    label: 'NFL',
    api: 'American Football',
    icon: Icons.sports_football,
  ),
  (label: 'Béisbol', api: 'Baseball', icon: Icons.sports_baseball),
  (label: 'Hockey', api: 'Ice Hockey', icon: Icons.sports_hockey),
  (label: 'Motor', api: 'Motorsport', icon: Icons.sports_motorsports),
  (label: 'Tenis', api: 'Tennis', icon: Icons.sports_tennis),
  (label: 'Combate', api: 'Fighting', icon: Icons.sports_mma),
];

String _subtitle(String competition, DateTime startsAt) {
  final time = DateFormat.Hm().format(startsAt);
  return '$competition · $time';
}

class SportsHubScreen extends ConsumerStatefulWidget {
  const SportsHubScreen({super.key});

  @override
  ConsumerState<SportsHubScreen> createState() => _SportsHubScreenState();
}

class _SportsHubScreenState extends ConsumerState<SportsHubScreen> {
  String selectedSport = 'Soccer';

  @override
  Widget build(BuildContext context) {
    final eventsState = ref.watch(sportsEventsProvider(selectedSport));
    final events = eventsState.asData?.value ?? const <SportsEvent>[];
    final channels = ref.watch(liveChannelsProvider).asData?.value ??
        const <LiveChannel>[];
    final programs = ref.watch(epgProgramsProvider).asData?.value ??
        const <EpgProgram>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sports Hub'),
        actions: [
          IconButton(
            tooltip: 'Actualizar eventos',
            onPressed: () => ref.invalidate(
              sportsEventsProvider(selectedSport),
            ),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Deportes de hoy',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          const Text(
            'POTV obtiene únicamente el calendario deportivo. La reproducción se resuelve con las fuentes configuradas localmente en tu dispositivo.',
            style: TextStyle(color: Colors.white60),
          ),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final sport in _sports)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      avatar: Icon(sport.icon, size: 18),
                      label: Text(sport.label),
                      selected: selectedSport == sport.api,
                      onSelected: (_) {
                        setState(() => selectedSport = sport.api);
                      },
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          if (eventsState.isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (eventsState.hasError)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'No pudimos cargar los eventos deportivos.\n' +
                      eventsState.error.toString(),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          for (final event in events)
            _SportsEventCard(
              event: event,
              channels: channels,
              programs: programs,
            ),
          if (!eventsState.isLoading &&
              !eventsState.hasError &&
              events.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'No hay eventos de esta categoría para hoy.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SportsEventCard extends StatelessWidget {
  final SportsEvent event;
  final List<LiveChannel> channels;
  final List<EpgProgram> programs;

  const _SportsEventCard({
    required this.event,
    required this.channels,
    required this.programs,
  });

  @override
  Widget build(BuildContext context) {
    const resolver = SportsChannelResolver();
    final matches = resolver.resolve(
      event: event,
      channels: channels,
      programs: programs,
    );
    final best = matches.isEmpty ? null : matches.first;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 10,
        ),
        leading: Icon(_sportIcon(event.sport)),
        title: Text(
          event.title,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_subtitle(event.competition, event.startsAt)),
            if (event.isLive)
              const Text(
                'EN VIVO',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Colors.redAccent,
                ),
              ),
            if (best != null)
              Text(
                best.program?.title ?? 'Disponible en ' + best.channel.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70),
              ),
          ],
        ),
        trailing: FilledButton(
          onPressed: best == null
              ? null
              : () => context.push('/player', extra: best.channel.stream),
          child: Text(best == null ? 'SIN FUENTE' : 'VER'),
        ),
      ),
    );
  }

  IconData _sportIcon(String sport) {
    final value = sport.toLowerCase();
    if (value.contains('soccer')) return Icons.sports_soccer;
    if (value.contains('basket')) return Icons.sports_basketball;
    if (value.contains('american')) return Icons.sports_football;
    if (value.contains('baseball')) return Icons.sports_baseball;
    if (value.contains('hockey')) return Icons.sports_hockey;
    if (value.contains('motor')) return Icons.sports_motorsports;
    if (value.contains('tennis')) return Icons.sports_tennis;
    if (value.contains('fight') || value.contains('boxing')) {
      return Icons.sports_mma;
    }
    return Icons.sports;
  }
}
