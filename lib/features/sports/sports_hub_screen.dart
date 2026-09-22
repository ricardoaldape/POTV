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

String _subtitle(String competition, DateTime startsAt) {
  final time = DateFormat.Hm().format(startsAt);
  return '$competition · $time';
}

class SportsHubScreen extends ConsumerWidget {
  const SportsHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(sportsEventsProvider);
    final channels = ref.watch(liveChannelsProvider).asData?.value ??
        const <LiveChannel>[];
    final programs = ref.watch(epgProgramsProvider).asData?.value ??
        const <EpgProgram>[];

    return Scaffold(
      appBar: AppBar(title: const Text('Sports Hub')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Deportes de hoy',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          const Text(
            'Los eventos se relacionan con las fuentes y la guía configuradas localmente. POTV no recibe tus URLs ni tus listas.',
            style: TextStyle(color: Colors.white60),
          ),
          const SizedBox(height: 22),
          for (final event in events)
            _SportsEventCard(
              event: event,
              channels: channels,
              programs: programs,
            ),
          if (events.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'No hay eventos cargados para hoy.',
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
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 10,
        ),
        leading: Icon(
          event.sport == 'Fútbol'
              ? Icons.sports_soccer
              : Icons.sports_basketball,
        ),
        title: Text(
          event.title,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_subtitle(event.competition, event.startsAt)),
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
}
