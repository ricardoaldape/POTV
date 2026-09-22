import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../data/live_tv/built_in_live_sources.dart';
import '../../data/live_tv/live_tv_repository.dart';
import '../../data/sports/sports_repository.dart';
import '../../domain/models/epg_program.dart';
import '../../domain/models/live_channel.dart';
import '../../domain/models/playback_session.dart';
import '../../domain/models/sports_event.dart';
import '../../domain/services/sports_channel_resolver.dart';
import 'sports_channel_rail.dart';

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
  DateTime selectedDay = DateUtils.dateOnly(DateTime.now());

  List<LiveChannel> _mergeChannels(
    List<LiveChannel> primary,
    List<LiveChannel> secondary,
  ) {
    final seen = <String>{};
    final result = <LiveChannel>[];

    for (final channel in [...primary, ...secondary]) {
      final key = [
        channel.epgId?.trim().toLowerCase() ?? '',
        channel.name.trim().toLowerCase(),
        channel.stream.uri.toString(),
      ].join('|');
      if (seen.add(key)) result.add(channel);
    }

    return result;
  }

  Future<void> _pickDate() async {
    final value = await showDatePicker(
      context: context,
      initialDate: selectedDay,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (value != null) {
      setState(() => selectedDay = DateUtils.dateOnly(value));
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = (day: selectedDay, sport: selectedSport);
    final eventsState = ref.watch(sportsEventsProvider(query));
    final events = eventsState.asData?.value ?? const <SportsEvent>[];
    final liveChannels = ref.watch(liveChannelsProvider).asData?.value ??
        const <LiveChannel>[];
    final sportsChannelsState = ref.watch(builtInSportsChannelsProvider);
    final sportsChannels =
        sportsChannelsState.asData?.value ?? const <LiveChannel>[];
    final channels = _mergeChannels(liveChannels, sportsChannels);
    final programs = ref.watch(epgProgramsProvider).asData?.value ??
        const <EpgProgram>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sports Hub'),
        actions: [
          IconButton(
            tooltip: 'Actualizar eventos',
            onPressed: () => ref.invalidate(
              sportsEventsProvider(query),
            ),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Deportes · ${DateFormat('EEE d MMM').format(selectedDay)}',
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'POTV obtiene únicamente el calendario deportivo. La reproducción se resuelve con las fuentes configuradas localmente en tu dispositivo.',
            style: TextStyle(color: Colors.white60),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ChoiceChip(
                label: const Text('Hoy'),
                selected: DateUtils.isSameDay(
                  selectedDay,
                  DateTime.now(),
                ),
                onSelected: (_) {
                  setState(() {
                    selectedDay = DateUtils.dateOnly(DateTime.now());
                  });
                },
              ),
              ChoiceChip(
                label: const Text('Mañana'),
                selected: DateUtils.isSameDay(
                  selectedDay,
                  DateTime.now().add(const Duration(days: 1)),
                ),
                onSelected: (_) {
                  setState(() {
                    selectedDay = DateUtils.dateOnly(
                      DateTime.now().add(const Duration(days: 1)),
                    );
                  });
                },
              ),
              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_month),
                label: const Text('Calendario'),
              ),
            ],
          ),
          const SizedBox(height: 14),
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
          const SizedBox(height: 18),
          if (sportsChannelsState.isLoading)
            const LinearProgressIndicator(minHeight: 2),
          if (sportsChannels.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text(
              'Canales deportivos disponibles',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            SportsChannelRail(channels: sportsChannels),
          ],
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
                  'No pudimos cargar los eventos deportivos.\n${eventsState.error}',
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
                best.program?.title ?? 'Disponible en ${best.channel.name}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70),
              ),
          ],
        ),
        trailing: FilledButton(
          onPressed: best == null
              ? null
              : () {
                  final session = PlaybackSession(
                    title: event.title,
                    candidates: [
                      for (final match in matches) match.channel.stream,
                    ],
                  );
                  context.push('/player', extra: session);
                },
          child: Text(
            best == null
                ? 'SIN FUENTE'
                : matches.length > 1
                    ? 'VER · ${matches.length}'
                    : 'VER',
          ),
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
