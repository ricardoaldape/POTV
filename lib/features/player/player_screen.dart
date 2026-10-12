import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/debug/debug_log_provider.dart';
import '../../data/history/playback_history_repository.dart';
import '../../data/catalog/series_episode_repository.dart';
import '../../data/sources/unified_source_resolver.dart';
import '../../domain/models/playback_history_entry.dart';
import '../../domain/models/media_item.dart';
import '../../domain/services/stream_candidate_ranker.dart';
import '../../domain/models/playback_session.dart';
import '../../domain/models/stream_candidate.dart';
import 'secure_webview_player.dart';
import 'spanish_track_selector.dart';

class PlayerScreen extends ConsumerStatefulWidget {
  final PlaybackSession session;

  const PlayerScreen({
    super.key,
    required this.session,
  });

  factory PlayerScreen.fromExtra(Object? extra) {
    if (extra is PlaybackSession) {
      return PlayerScreen(session: extra);
    }
    if (extra is StreamCandidate) {
      return PlayerScreen(session: PlaybackSession.single(extra));
    }
    return PlayerScreen(
      session: PlaybackSession.single(
        StreamCandidate(
          id: 'invalid',
          label: 'Fuente no disponible',
          uri: Uri.parse('https://example.invalid'),
        ),
      ),
    );
  }

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  Player? player;
  VideoController? videoController;
  Timer? hideTimer;
  Timer? historyTimer;
  Timer? startupTimer;
  StreamSubscription<bool>? playingSubscription;
  bool _startupPlaying = false;
  DateTime? _startupStartedAt;
  StreamSubscription<String>? playerErrorSubscription;
  StreamSubscription<Tracks>? tracksSubscription;
  StreamSubscription<bool>? completedSubscription;
  bool _autoNextAttempted = false;
  bool _advancingEpisode = false;
  late PlaybackSession _session;
  bool _autoAudioSelected = false;
  bool _autoSubtitleSelected = false;
  bool _manualAudioSelected = false;
  bool _manualSubtitleSelected = false;
  bool controlsVisible = true;
  bool failoverInProgress = false;
  String? playbackError;
  late int currentIndex;
  final historyRepository = const PlaybackHistoryRepository();

  StreamCandidate get currentStream =>
      _session.candidates[currentIndex];

  @override
  void initState() {
    super.initState();
    _session = widget.session;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    currentIndex = widget.session.initialIndex
        .clamp(0, widget.session.candidates.length - 1)
        .toInt();
    unawaited(_openCurrent(notify: false));
    _armAutoHide();
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    hideTimer?.cancel();
    historyTimer?.cancel();
    startupTimer?.cancel();
    unawaited(playingSubscription?.cancel());
    unawaited(playerErrorSubscription?.cancel());
    unawaited(tracksSubscription?.cancel());
    unawaited(completedSubscription?.cancel());
    unawaited(_saveProgress());
    player?.dispose();
    super.dispose();
  }

  Future<void> _openCurrent({
    bool notify = true,
    Duration? resumeAt,
  }) async {
    historyTimer?.cancel();
    startupTimer?.cancel();
    _startupPlaying = false;
    _startupStartedAt = null;
    await playingSubscription?.cancel();
    playingSubscription = null;
    await playerErrorSubscription?.cancel();
    playerErrorSubscription = null;
    await tracksSubscription?.cancel();
    tracksSubscription = null;
    await completedSubscription?.cancel();
    completedSubscription = null;
    _autoNextAttempted = false;
    _autoAudioSelected = false;
    _autoSubtitleSelected = false;
    _manualAudioSelected = false;
    _manualSubtitleSelected = false;
    await _saveProgress();
    await player?.dispose();
    player = null;
    videoController = null;
    playbackError = null;

    var effectiveResumeAt = resumeAt;
    final playbackContext = widget.session.playbackContext;
    if (effectiveResumeAt == null && playbackContext != null) {
      final history = await historyRepository.get(playbackContext.historyKey);
      if (history != null && history.positionMs > 5000) {
        effectiveResumeAt = Duration(milliseconds: history.positionMs);
      }
    }

    while (true) {
      try {
        final inputUrl = currentStream.uri.toString();
        final inputLog =
            'Resolver: URL de entrada -> ${_safeLogUri(currentStream.uri)}';
        debugPrint(inputLog);
        addDebugLog(inputLog);

        if (currentStream.backend == PlaybackBackend.native) {
          final nextPlayer = Player();
          _startupStartedAt = DateTime.now();
          player = nextPlayer;
          videoController = VideoController(nextPlayer);

          // Start listening to `playing` state to detect successful startup.
          _startupPlaying = false;
          playingSubscription = nextPlayer.stream.playing.listen((isPlaying) {
            if (isPlaying) {
              _startupPlaying = true;
              final elapsedMs = DateTime.now()
                  .difference(_startupStartedAt ?? DateTime.now())
                  .inMilliseconds;
              addDebugLog("Player: arranque en ${elapsedMs}ms");
              startupTimer?.cancel();
              unawaited(playingSubscription?.cancel());
              playingSubscription = null;
            }
          });

          // Start the startup timeout before opening. If playback doesn't
          // start within 10s, trigger failover.
          startupTimer = Timer(const Duration(seconds: 10), () {
            if (!mounted) return;
            if (failoverInProgress) return;
            if (_startupPlaying) return;
            final msg = "Player: timeout de arranque para '${currentStream.label}' después de 10s → failover";
            addDebugLog(msg);
            unawaited(_autoFailover(msg));
          });

          await nextPlayer.open(
            Media(
              inputUrl,
              httpHeaders: currentStream.headers,
            ),
            play: true,
          );
          final externalAudioUri = currentStream.externalAudioUri;
          if (externalAudioUri != null) {
            await nextPlayer.setAudioTrack(
              AudioTrack.uri(
                externalAudioUri.toString(),
                title: 'Audio alternativo',
              ),
            );
          }
          playerErrorSubscription = nextPlayer.stream.error.listen(
            (message) => unawaited(_autoFailover(message)),
          );
          tracksSubscription = nextPlayer.stream.tracks.listen(
            (tracks) => _autoSelectSpanishTracks(nextPlayer, tracks),
          );
          completedSubscription = nextPlayer.stream.completed.listen(
            (completed) {
              if (completed && !_autoNextAttempted) {
                _autoNextAttempted = true;
                unawaited(_advanceEpisode());
              }
            },
          );
          _autoSelectSpanishTracks(nextPlayer, nextPlayer.state.tracks);
          if (effectiveResumeAt != null &&
              effectiveResumeAt > Duration.zero) {
            await nextPlayer.seek(effectiveResumeAt);
          }
          final finalStreamLog =
              'Resolver: URL final del stream -> ${_safeLogUri(currentStream.uri)}';
          debugPrint(finalStreamLog);
          addDebugLog(finalStreamLog);
          _armHistorySave();
        } else if (currentStream.backend == PlaybackBackend.external) {
          final opened = await launchUrl(
            currentStream.uri,
            mode: LaunchMode.externalApplication,
          );
          if (!opened) {
            throw StateError('No hay una aplicación disponible para abrirlo.');
          }
          final finalStreamLog =
              'Resolver: URL final del stream -> ${_safeLogUri(currentStream.uri)}';
          debugPrint(finalStreamLog);
          addDebugLog(finalStreamLog);
        }

        break;
      } catch (error, stack) {
        final errorLog = 'Resolver error: ${_redactError(error.toString())}';
        final stackLog = 'Resolver stack: $stack';
        debugPrint(errorLog);
        debugPrint(stackLog);
        addDebugLog(errorLog);
        addDebugLog(stackLog);

        await playerErrorSubscription?.cancel();
        playerErrorSubscription = null;
        await tracksSubscription?.cancel();
        tracksSubscription = null;
        await player?.dispose();
        player = null;
        videoController = null;

        if (currentIndex + 1 < widget.session.candidates.length) {
          currentIndex += 1;
          continue;
        }

        playbackError = error.toString();
        break;
      }
    }

    if (mounted && (notify || playbackError != null)) setState(() {});
  }

  Future<void> _autoFailover(String message) async {
    if (!mounted || failoverInProgress) return;
    if (currentIndex + 1 >= widget.session.candidates.length) {
      setState(() => playbackError = message);
      return;
    }

    failoverInProgress = true;
    final resumeAt = player?.state.position;
    currentIndex += 1;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 2),
          content: Text(
            'Ajustando la reproducción…',
          ),
        ),
      );
    }

    try {
      await _openCurrent(resumeAt: resumeAt);
    } finally {
      failoverInProgress = false;
    }
  }

  void _armHistorySave() {
    historyTimer?.cancel();
    if (widget.session.playbackContext == null) return;
    historyTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => unawaited(_saveProgress()),
    );
  }

  Future<void> _saveProgress() async {
    final playbackContext = widget.session.playbackContext;
    final p = player;
    if (playbackContext == null || p == null) return;

    final position = p.state.position;
    final duration = p.state.duration;
    if (position < const Duration(seconds: 2)) return;

    await historyRepository.save(
      PlaybackHistoryEntry(
        key: playbackContext.historyKey,
        mediaId: playbackContext.mediaId,
        mediaType: playbackContext.mediaType,
        title: playbackContext.title,
        externalId: playbackContext.externalId,
        season: playbackContext.season,
        episode: playbackContext.episode,
        poster: playbackContext.poster,
        positionMs: position.inMilliseconds,
        durationMs: duration.inMilliseconds,
        updatedAt: DateTime.now(),
      ),
    );
  }

  void _armAutoHide() {
    hideTimer?.cancel();
    hideTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => controlsVisible = false);
    });
  }

  void _showControls() {
    if (!mounted) return;
    setState(() => controlsVisible = true);
    _armAutoHide();
  }

  void _toggleControls() {
    setState(() => controlsVisible = !controlsVisible);
    if (controlsVisible) _armAutoHide();
  }

  Future<void> _switchServer(int index) async {
    if (index == currentIndex) {
      if (mounted) Navigator.of(context).pop();
      return;
    }

    final resumeAt = player?.state.position;
    if (mounted) Navigator.of(context).pop();
    currentIndex = index;
    await _openCurrent(resumeAt: resumeAt);
    _showControls();
  }

  Future<void> _showServers() async {
    _showControls();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0D1418),
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            const ListTile(
              title: Text(
                'Opciones de reproducción',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            for (var i = 0; i < widget.session.candidates.length; i++)
              ListTile(
                leading: Icon(
                  i == currentIndex
                      ? Icons.check_circle
                      : Icons.circle_outlined,
                ),
                title: Text('Opción ${i + 1}'),
                subtitle: Text(
                  [
                    widget.session.candidates[i].language,
                    widget.session.candidates[i].quality,
                  ].whereType<String>().join(' · '),
                ),
                onTap: () => _switchServer(i),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _advanceEpisode() async {
    if (!mounted || _advancingEpisode || _session.isLive) return;
    final current = _session.playbackContext;
    if (current == null ||
        current.mediaType != 'tv' ||
        current.season == null ||
        current.episode == null) return;

    _advancingEpisode = true;
    try {
      final item = MediaItem(
        id: current.mediaId,
        type: MediaType.tv,
        title: current.title,
        externalId: current.externalId,
      );
      final episodes = await ref.read(seriesEpisodeRepositoryProvider)
          .load(item).timeout(const Duration(seconds: 9));
      if (!mounted || episodes.isEmpty) return;
      final index = episodes.indexWhere((entry) =>
          entry.season == current.season &&
          entry.episode == current.episode);
      if (index < 0 || index + 1 >= episodes.length) return;
      final nextEpisode = episodes[index + 1];

      final candidates = await ref.read(unifiedSourceResolverProvider).resolve(
        mediaType: 'tv',
        mediaId: current.mediaId.toString(),
        externalId: current.externalId,
        title: current.title,
        season: nextEpisode.season,
        episode: nextEpisode.episode,
      ).timeout(const Duration(seconds: 19));
      final playable = const StreamCandidateRanker().rank(
        candidates.where((candidate) =>
          candidate.backend == PlaybackBackend.native,
        ).toList(growable: false),
      );
      if (playable.isEmpty || !mounted) return;

      // Store progress against the old episode before switching context.
      await _saveProgress();
      historyTimer?.cancel();
      await completedSubscription?.cancel();
      completedSubscription = null;
      final previousPlayer = player;
      player = null;
      await previousPlayer?.dispose();

      _session = PlaybackSession(
        title: '${current.title} · T${nextEpisode.season} E${nextEpisode.episode}',
        candidates: playable,
        playbackContext: PlaybackContext(
          mediaId: current.mediaId,
          mediaType: current.mediaType,
          title: current.title,
          externalId: current.externalId,
          season: nextEpisode.season,
          episode: nextEpisode.episode,
          poster: current.poster,
        ),
      );
      currentIndex = 0;
      await _openCurrent(resumeAt: Duration.zero);
    } catch (_) {
      addDebugLog('Player: el siguiente episodio no está disponible');
    } finally {
      _advancingEpisode = false;
    }
  }

    void _autoSelectSpanishTracks(Player current, Tracks tracks) {
    if (!mounted || player != current) return;

    final spanishAudio = SpanishTrackSelector.preferredAudio(tracks.audio);
    final spanishSubtitle =
        SpanishTrackSelector.preferredSubtitle(tracks.subtitle);

    if (!_manualAudioSelected &&
        !_autoAudioSelected &&
        spanishAudio != null &&
        currentStream.externalAudioUri == null) {
      _autoAudioSelected = true;
      unawaited(current.setAudioTrack(spanishAudio).catchError((Object _) {
        addDebugLog('Player: no se pudo seleccionar audio español');
      }));
    }

    if (_manualSubtitleSelected) return;
    if (_autoAudioSelected && _autoSubtitleSelected) {
      _autoSubtitleSelected = false;
      unawaited(current.setSubtitleTrack(SubtitleTrack.no()).catchError(
        (Object _) => addDebugLog('Player: fallo desactivando subtítulos'),
      ));
    } else if (!_autoAudioSelected &&
        !_autoSubtitleSelected &&
        spanishSubtitle != null) {
      _autoSubtitleSelected = true;
      unawaited(current.setSubtitleTrack(spanishSubtitle).catchError(
        (Object _) => addDebugLog('Player: no se pudo seleccionar subtítulo español'),
      ));
    }
  }

    Future<void> _showAudioTracks() async {
    final p = player;
    if (p == null) return;
    final tracks = p.state.tracks.audio;
    final selected = p.state.track.audio;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0D1418),
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Audio')),
            for (final track in tracks)
              ListTile(
                leading: Icon(
                  track.id == selected.id
                      ? Icons.check_circle
                      : Icons.circle_outlined,
                ),
                title: Text(
                  track.title ?? track.language ?? 'Pista ${track.id}',
                ),
                onTap: () {
                  _manualAudioSelected = true;
                  p.setAudioTrack(track);
                  Navigator.of(context).pop();
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showSubtitleTracks() async {
    final p = player;
    if (p == null) return;
    final tracks = p.state.tracks.subtitle;
    final selected = p.state.track.subtitle;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0D1418),
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Subtítulos')),
            for (final track in tracks)
              ListTile(
                leading: Icon(
                  track.id == selected.id
                      ? Icons.check_circle
                      : Icons.circle_outlined,
                ),
                title: Text(
                  track.id == 'no'
                      ? 'Desactivados'
                      : track.title ?? track.language ?? 'Pista ${track.id}',
                ),
                onTap: () {
                  _manualSubtitleSelected = true;
                  p.setSubtitleTrack(track);
                  Navigator.of(context).pop();
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showVideoTracks() async {
    final p = player;
    if (p == null) return;
    final tracks = p.state.tracks.video;
    final selected = p.state.track.video;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0D1418),
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Calidad')),
            for (final track in tracks)
              ListTile(
                leading: Icon(
                  track.id == selected.id
                      ? Icons.check_circle
                      : Icons.circle_outlined,
                ),
                title: Text(
                  track.title ??
                      (track.h == null
                          ? 'Pista ${track.id}'
                          : '${track.h}p'),
                ),
                onTap: () {
                  p.setVideoTrack(track);
                  Navigator.of(context).pop();
                },
              ),
          ],
        ),
      ),
    );
  }

  String _redactError(String message) => message.replaceAll(
        RegExp(r'https?://\S+'),
        '[media-url]',
      );

  String _safeLogUri(Uri uri) => uri.replace(
        userInfo: '',
        query: null,
        fragment: null,
      ).toString();

  void _exitPlayer() {
    if (!mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape ||
        event.logicalKey == LogicalKeyboardKey.backspace) {
      _exitPlayer();
      return KeyEventResult.handled;
    }
    _showControls();

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.mediaPlayPause ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter) {
      player?.playOrPause();
      return KeyEventResult.handled;
    }

    final p = player;
    if (p != null && key == LogicalKeyboardKey.arrowLeft) {
      final target = p.state.position - const Duration(seconds: 10);
      p.seek(target.isNegative ? Duration.zero : target);
      return KeyEventResult.handled;
    }
    if (p != null && key == LogicalKeyboardKey.arrowRight) {
      final target = p.state.position + const Duration(seconds: 10);
      p.seek(target);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final p = player;

    final Widget content;
    if (playbackError != null) {
      content = _PlaybackFailureView(
        message: 'No pudimos reproducir este video. Prueba otra opción o inténtalo más tarde.',
        hasAlternatives: widget.session.candidates.length > 1,
        onRetry: () {
          currentIndex = 0;
          unawaited(_openCurrent());
        },
        onServers: _showServers,
      );
    } else {
      content = switch (currentStream.backend) {
        PlaybackBackend.native => videoController == null
            ? const Center(child: CircularProgressIndicator())
            : Video(
                controller: videoController!,
                controls: NoVideoControls,
                fit: BoxFit.contain,
              ),
        PlaybackBackend.webView => SecureWebViewPlayer(
            key: ValueKey(currentStream.id),
            stream: currentStream,
          ),
        PlaybackBackend.external => _ExternalPlaybackView(
            stream: currentStream,
            onOpen: () => launchUrl(
              currentStream.uri,
              mode: LaunchMode.externalApplication,
            ),
          ),
      };
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggleControls,
          child: Stack(
            fit: StackFit.expand,
            children: [
              content,
              IgnorePointer(
                ignoring: !controlsVisible,
                child: AnimatedOpacity(
                  opacity: controlsVisible ? 1 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: _PlayerOverlay(
                    title: widget.session.title,
                    stream: currentStream,
                    player: p,
                    isLive: widget.session.isLive,
                    onBack: _exitPlayer,
                    onAudio: p == null ? null : _showAudioTracks,
                    onSubtitles: p == null ? null : _showSubtitleTracks,
                    onQuality: p == null ? null : _showVideoTracks,
                    onServers: _showServers,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExternalPlaybackView extends StatelessWidget {
  final StreamCandidate stream;
  final Future<bool> Function() onOpen;

  const _ExternalPlaybackView({
    required this.stream,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.open_in_new_rounded, size: 54),
              const SizedBox(height: 16),
              Text(
                'Reproducción externa',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'El contenido se abrirá en una aplicación o navegador compatible.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () => onOpen(),
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Abrir'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaybackFailureView extends StatelessWidget {
  final String message;
  final bool hasAlternatives;
  final VoidCallback onRetry;
  final VoidCallback onServers;

  const _PlaybackFailureView({
    required this.message,
    required this.hasAlternatives,
    required this.onRetry,
    required this.onServers,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, size: 54),
              const SizedBox(height: 14),
              const Text(
                'No se pudo iniciar la reproducción',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white60),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Reintentar'),
                  ),
                  if (hasAlternatives)
                    FilledButton.tonalIcon(
                      onPressed: onServers,
                      icon: const Icon(Icons.dns_outlined),
                      label: const Text('Opciones'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayerOverlay extends StatelessWidget {
  final String title;
  final StreamCandidate stream;
  final Player? player;
  final bool isLive;
  final VoidCallback onBack;
  final VoidCallback? onAudio;
  final VoidCallback? onSubtitles;
  final VoidCallback? onQuality;
  final VoidCallback onServers;

  const _PlayerOverlay({
    required this.title,
    required this.stream,
    required this.player,
    required this.isLive,
    required this.onBack,
    required this.onAudio,
    required this.onSubtitles,
    required this.onQuality,
    required this.onServers,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xCC000000),
            Color(0x00000000),
            Color(0xDD000000),
          ],
          stops: [0, 0.45, 1],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  IconButton.filledTonal(
                    onPressed: onBack,
                    icon: const Icon(Icons.arrow_back),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            if (player != null)
              StreamBuilder<bool>(
                stream: player!.stream.playing,
                initialData: player!.state.playing,
                builder: (context, snapshot) => IconButton.filled(
                  iconSize: 42,
                  onPressed: player!.playOrPause,
                  icon: Icon(
                    snapshot.data == true
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                  ),
                ),
              ),
            const Spacer(),
            if (player != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: _Timeline(player: player!, isLive: isLive),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
              child: Column(
                children: [
                  Text(
                    [
                      stream.language,
                      stream.quality,
                    ].whereType<String>().join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    alignment: WrapAlignment.center,
                    children: [
                      if (stream.backend == PlaybackBackend.native) ...[
                        _ActionButton(
                          icon: Icons.audiotrack,
                          label: 'Audio',
                          onPressed: onAudio,
                        ),
                        _ActionButton(
                          icon: Icons.subtitles,
                          label: 'Subtítulos',
                          onPressed: onSubtitles,
                        ),
                      ],
                      _ActionButton(
                        icon: Icons.high_quality,
                        label: 'Calidad',
                        onPressed: onQuality,
                      ),
                      _ActionButton(
                        icon: Icons.dns_outlined,
                        label: 'Opciones',
                        onPressed: onServers,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  final Player player;
  final bool isLive;

  const _Timeline({required this.player, required this.isLive});

  String _format(Duration value) {
    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: player.stream.duration,
      initialData: player.state.duration,
      builder: (context, durationSnapshot) {
        final duration = durationSnapshot.data ?? Duration.zero;
        return StreamBuilder<Duration>(
          stream: player.stream.position,
          initialData: player.state.position,
          builder: (context, positionSnapshot) {
            final position = positionSnapshot.data ?? Duration.zero;
            final durationMs = duration.inMilliseconds;
            final max = durationMs <= 0 ? 1.0 : durationMs.toDouble();
            final value = position.inMilliseconds
                .clamp(0, durationMs <= 0 ? 0 : durationMs)
                .toDouble();

            return Row(
              children: [
                Text(_format(position)),
                Expanded(
                  child: Slider(
                    min: 0,
                    max: max,
                    value: value.clamp(0, max),
                    onChanged: durationMs <= 0
                        ? null
                        : (next) => player.seek(
                              Duration(milliseconds: next.round()),
                            ),
                  ),
                ),
                Text(durationMs <= 0 ? (isLive ? 'EN VIVO' : '--:--') : _format(duration)),
              ],
            );
          },
        );
      },
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
    );
  }
}
