import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/sports/sports_repository.dart';

String _subtitle(String competition, DateTime startsAt) {
  final time = DateFormat.Hm().format(startsAt);
  return '$competition · $time';
}

class SportsHubScreen extends ConsumerWidget {
  const SportsHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(sportsEventsProvider);
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
            'POTV identifica el evento; la reproducción se resolverá únicamente con las fuentes configuradas localmente por el usuario.',
            style: TextStyle(color: Colors.white60),
          ),
          const SizedBox(height: 22),
          for (final event in events)
            Card(
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
                subtitle: Text(_subtitle(event.competition, event.startsAt)),
                trailing: FilledButton(
                  onPressed: null,
                  child: Text(event.isLive ? 'VER' : 'PRÓXIMO'),
                ),
              ),
            ),
          const SizedBox(height: 14),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: Text(
                'Alpha: el calendario usa datos de demostración. El siguiente bloque conectará un proveedor de datos deportivos y el resolver local de canales/fuentes.',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
