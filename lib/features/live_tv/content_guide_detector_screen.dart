import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../data/catalog/partner_content_repository.dart';
import '../../data/live_tv/built_in_live_sources.dart';
import '../../data/live_tv/live_tv_repository.dart';
import '../../data/sources/stream_candidate_probe.dart';
import '../../domain/models/epg_program.dart';
import '../../domain/models/live_channel.dart';
import '../../domain/models/playback_session.dart';
import '../../domain/models/sports_event.dart';
import '../../domain/services/guide_content_detector.dart';
import '../../domain/services/live_tv_organizer.dart';

/// Opens the original channel or event directly from an always-current guide.
/// No additional stream URL is manufactured or leaked through programme data.
class ContentGuideDetectorScreen extends ConsumerStatefulWidget {
  const ContentGuideDetectorScreen({super.key});

  @override
  ConsumerState<ContentGuideDetectorScreen> createState() =>
      _ContentGuideDetectorScreenState();
}

class _ContentGuideDetectorScreenState
    extends ConsumerState<ContentGuideDetectorScreen>
    with WidgetsBindingObserver {
  static const _detector = GuideContentDetector();
  static const _organizer = LiveTvOrganizer();

  Timer? _minuteTimer;
  Timer? _catalogTimer;
  Timer? _epgTimer;
  DateTime _now = DateTime.now();
  String _search = '';
  bool? _sports;
  bool _programmesOnly = false;
  String? _opening;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startTimers();
  }

  void _startTimers() {
    _minuteTimer ??= Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    _catalogTimer ??= Timer.periodic(const Duration(minutes: 2), (_) {
      if (mounted) ref.invalidate(partnerContentProvider);
    });
    _epgTimer ??= Timer.periodic(const Duration(minutes: 30), (_) {
      if (mounted) ref.invalidate(epgProgramsProvider);
    });
  }

  void _stopTimers() {
    _minuteTimer?.cancel();
    _minuteTimer = null;
    _catalogTimer?.cancel();
    _catalogTimer = null;
    _epgTimer?.cancel();
    _epgTimer = null;
  }

  @override
  void dispose() {
    _stopTimers();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      setState(() => _now = DateTime.now());
      ref.invalidate(partnerContentProvider);
      ref.invalidate(epgProgramsProvider);
      _startTimers();
    } else {
      _stopTimers();
    }
  }

  void _refresh() {
    setState(() => _now = DateTime.now());
    ref.invalidate(partnerContentProvider);
    ref.invalidate(liveChannelsProvider);
    ref.invalidate(builtInSportsChannelsProvider);
    ref.invalidate(epgProgramsProvider);
  }

  void _notice(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _open(DetectedGuideItem item) async {
    if (_opening != null) return;
    setState(() => _opening = item.id);
    try {
      if (item.event case final SportsEvent event) {
        // Rehydrate signed event links at click-time.
        final latest = await ref.read(partnerContentRepositoryProvider).load();
        if (!mounted) return;
        final matches = latest.sportsEvents.where((e) => e.id == event.id &&
            e.isLive && e.streams.isNotEmpty);
        if (matches.isEmpty) {
          _notice('El evento terminó o su señal ya no está disponible.');
          ref.invalidate(partnerContentProvider);
          return;
        }
        final currentEvent = matches.first;
        context.push('/player', extra: PlaybackSession(
          title: currentEvent.title,
          candidates: currentEvent.streams,
          isLive: true,
        ));
        return;
      }

      var channel = item.channel!;
      if (channel.id.startsWith('partner:')) {
        final latest = await ref.read(partnerContentRepositoryProvider).load();
        if (!mounted) return;
        final matches = [
          ...latest.channels,
          ...latest.sportsChannels,
        ].where((c) => c.id == channel.id);
        if (matches.isEmpty) {
          _notice('El canal ya no está disponible en el catálogo.');
          ref.invalidate(partnerContentProvider);
          return;
        }
        channel = matches.first;
      }

      final playable = channel.id.startsWith('partner:')
          ? channel.playbackCandidates
          : await ref.read(streamCandidateProbeProvider).preferReachable(
              channel.playbackCandidates,
              dropDeadWhenCertain: true,
            );
      if (!mounted) return;
      if (playable.isEmpty) {
        _notice('La señal no responde. Intenta nuevamente.');
        return;
      }
      context.push('/player', extra: PlaybackSession(
        title: channel.name,
        candidates: playable,
        isLive: true,
      ));
    } catch (_) {
      _notice('No fue posible abrir la señal en este momento.');
    } finally {
      if (mounted) setState(() => _opening = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final partnerState = ref.watch(partnerContentProvider);
    final channelsState = ref.watch(liveChannelsProvider);
    final sportsState = ref.watch(builtInSportsChannelsProvider);
    final epgState = ref.watch(epgProgramsProvider);
    final partner = partnerState.asData?.value;

    final channels = _organizer.merge(
      partner: partner?.channels ?? const <LiveChannel>[],
      local: [
        ...ref.watch(starterMexicoChannelsProvider),
        ...channelsState.asData?.value ?? const <LiveChannel>[],
      ],
      partnerSports: partner?.sportsChannels ?? const <LiveChannel>[],
      publicSports: [
        ...ref.watch(starterSportsChannelsProvider),
        ...sportsState.asData?.value ?? const <LiveChannel>[],
      ],
    );
    final programs = [
      ...partner?.guidePrograms ?? const <EpgProgram>[],
      ...epgState.asData?.value ?? const <EpgProgram>[],
    ];
    final items = _detector.build(
      channels: channels,
      programs: programs,
      events: partner?.sportsEvents ?? const <SportsEvent>[],
      now: _now,
    );
    final visible = _detector.filter(
      items,
      search: _search,
      sports: _sports,
      withProgrammeOnly: _programmesOnly,
    );
    final loading = partnerState.isLoading ||
        channelsState.isLoading || sportsState.isLoading || epgState.isLoading;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detector de contenido para parrilla'),
        actions: [
          IconButton(
            tooltip: 'Actualizar programación',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '¿Qué están transmitiendo?',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                const Text(
                  'Consulta la programación y toca un canal o evento para verlo.',
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('guide-detector-search'),
                  onChanged: (text) => setState(() => _search = text),
                  decoration: const InputDecoration(
                    hintText: 'Buscar canal, película, programa o partido',
                    prefixIcon: Icon(Icons.search_rounded),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('Todo'),
                      selected: _sports == null,
                      onSelected: (_) => setState(() => _sports = null),
                    ),
                    ChoiceChip(
                      label: const Text('TV'),
                      selected: _sports == false,
                      onSelected: (_) => setState(() => _sports = false),
                    ),
                    ChoiceChip(
                      label: const Text('Deportes'),
                      selected: _sports == true,
                      onSelected: (_) => setState(() => _sports = true),
                    ),
                    FilterChip(
                      label: const Text('Con programación'),
                      selected: _programmesOnly,
                      onSelected: (v) => setState(() => _programmesOnly = v),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${visible.length} señales y eventos · ${DateFormat.Hm().format(_now)}',
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ],
            ),
          ),
          if (loading) const LinearProgressIndicator(minHeight: 2),
          if (epgState.hasError)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                'La guía externa no respondió. Se muestran los datos disponibles.',
                style: TextStyle(color: Colors.orangeAccent, fontSize: 12),
              ),
            ),
          Expanded(
            child: visible.isEmpty
                ? Center(
                    child: Text(
                      loading ? 'Consultando programación…' :
                      'No hay resultados para esta búsqueda.',
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.builder(
                    key: const ValueKey('guide-detector-list'),
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 24),
                    itemCount: visible.length,
                    itemBuilder: (context, index) {
                      final item = visible[index];
                      final current = item.currentTitle;
                      final next = item.nextTitle;
                      final startsAt = item.startsAt;
                      final endsAt = item.endsAt;
                      final progress = startsAt == null || endsAt == null ||
                              !endsAt.isAfter(startsAt)
                          ? null
                          : (_now.difference(startsAt).inMilliseconds /
                                endsAt.difference(startsAt).inMilliseconds)
                              .clamp(0.0, 1.0).toDouble();
                      final label = current == null
                          ? 'Sin información de programación'
                          : item.event != null
                              ? 'EVENTO EN VIVO · $current'
                              : 'AHORA · $current';
                      final timeLabel = startsAt == null
                          ? ''
                          : ' · ${DateFormat.Hm().format(startsAt)}'
                            '${endsAt == null ? '' : '–${DateFormat.Hm().format(endsAt)}'}';
                      return Card(
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          key: ValueKey('guide-detector-${item.id}'),
                          onTap: _opening != null ? null : () => _open(item),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(item.isSports
                                        ? Icons.sports_rounded
                                        : Icons.live_tv_rounded),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        item.channelName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    if (_opening == item.id)
                                      const SizedBox(
                                        width: 20, height: 20,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    else
                                      const Icon(Icons.play_circle_rounded),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '$label$timeLabel',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: current == null
                                        ? Colors.white60
                                        : Colors.white,
                                  ),
                                ),
                                if (progress != null) ...[
                                  const SizedBox(height: 8),
                                  LinearProgressIndicator(value: progress, minHeight: 3),
                                ],
                                if (next != null) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    'Después · $next',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
