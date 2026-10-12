import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/security/media_url_logging.dart';
import '../../data/addons/stremio_addon_repository.dart';
import '../../data/addons/stremio_subtitle_service.dart';
import '../../data/debug/debug_log_provider.dart';
import '../../data/history/playback_history_repository.dart';
import '../../data/history/playback_metrics_repository.dart';
import '../../data/history/stream_server_health_repository.dart';
import '../../data/sources/playback_preparation_service.dart';
import '../../domain/models/playback_history_entry.dart';
import '../../domain/models/playback_session.dart';
import '../../domain/models/stream_candidate.dart';
import '../../domain/services/playback_language_selector.dart';
import 'media3_player_surface.dart';
import 'player_preferences.dart';
import 'secure_webview_player.dart';

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
  Media3PlayerController? media3Controller;
  Media3PlayerState? media3State;
  Duration? media3ResumeAt;
  PlayerPreferences playerPreferences = const PlayerPreferences();
  bool preferencesLoaded = false;
  bool media3Ready = false;
  Timer? media3StateTimer;
  Timer? nextPreloadTimer;
  Timer? hideTimer;
  Timer? historyTimer;
  Timer? startupTimer;
  StreamSubscription<bool>? playingSubscription;
  StreamSubscription<bool>? completedSubscription;
  StreamSubscription<Tracks>? _tracksSubscription;
  final _languageSelector = const PlaybackLanguageSelector();
  List<StremioSubtitle> _externalSubtitleOptions = const [];
  bool _audioAutoSelected = false;
  bool _subtitleAutoSelected = false;
  bool _subtitleUserSelected = false;
  bool _startupPlaying = false;
  DateTime? _playbackStartedAt;
  int _openGeneration = 0;
  int _consecutiveInterruptions = 0;
  bool _handlingPlaybackError = false;
  bool _advancingEpisode = false;
  StreamSubscription<String>? playerErrorSubscription;
  bool controlsVisible = true;
  bool failoverInProgress = false;
  String? playbackError;
  late int currentIndex;
  final historyRepository = const PlaybackHistoryRepository();
  final metricsRepository = const PlaybackMetricsRepository();
  final serverHealthRepository = const StreamServerHealthRepository();

  String get _serverMediaKey =>
      widget.session.playbackContext?.historyKey ??
      'live:${widget.session.title}';


  StreamCandidate get currentStream =>
      widget.session.candidates[currentIndex];

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    currentIndex = widget.session.initialIndex
        .clamp(0, widget.session.candidates.length - 1)
        .toInt();
    unawaited(_initializePlayback());
    _armAutoHide();
  }

  Future<void> _initializePlayback() async {
    playerPreferences = await PlayerPreferences.load();
    if (!mounted) return;
    setState(() => preferencesLoaded = true);
    await _openCurrent(notify: false);
  }

  @override
  void dispose() {
    _openGeneration++;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    hideTimer?.cancel();
    historyTimer?.cancel();
    startupTimer?.cancel();
    media3StateTimer?.cancel();
    nextPreloadTimer?.cancel();
    media3Controller?.dispose();
    unawaited(playingSubscription?.cancel());
    unawaited(completedSubscription?.cancel());
    unawaited(_tracksSubscription?.cancel());
    unawaited(playerErrorSubscription?.cancel());
    unawaited(_saveProgress());
    final started = _playbackStartedAt;
    if (started != null) {
      unawaited(
        metricsRepository.recordWatchTime(
          _serverMediaKey,
          DateTime.now().difference(started),
        ),
      );
    }
    player?.dispose();
    super.dispose();
  }

  Future<void> _openCurrent({
    bool notify = true,
    Duration? resumeAt,
  }) async {
    final generation = ++_openGeneration;
    historyTimer?.cancel();
    startupTimer?.cancel();
    _startupPlaying = false;
    await playingSubscription?.cancel();
    playingSubscription = null;
    await completedSubscription?.cancel();
    completedSubscription = null;
    nextPreloadTimer?.cancel();
    nextPreloadTimer = null;
    await _tracksSubscription?.cancel();
    _tracksSubscription = null;
    _audioAutoSelected = false;
    _subtitleAutoSelected = false;
    _subtitleUserSelected = false;
    _externalSubtitleOptions = const [];
    await playerErrorSubscription?.cancel();
    playerErrorSubscription = null;
    await _saveProgress();
    await player?.dispose();
    player = null;
    videoController = null;
    media3StateTimer?.cancel();
    media3StateTimer = null;
    media3Controller?.dispose();
    media3Controller = null;
    media3State = null;
    media3ResumeAt = null;
    media3Ready = false;
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
        final inputLog = 'Resolver: URL de entrada -> ${safeMediaUrlForLog(currentStream.uri)}';
        debugPrint(inputLog);
        addDebugLog(inputLog);

        if (currentStream.backend == PlaybackBackend.native) {
          if (Platform.isAndroid) {
            media3ResumeAt = effectiveResumeAt;
            media3Ready = true;
            _armHistorySave();
            break;
          }

          final nextPlayer = Player();
          player = nextPlayer;
          videoController = VideoController(nextPlayer);
          completedSubscription = nextPlayer.stream.completed.listen((ended) {
            if (ended && mounted && generation == _openGeneration) {
              unawaited(_autoplayNextEpisode());
            }
          });

          _tracksSubscription = nextPlayer.stream.tracks.listen((tracks) {
            if (!mounted || generation != _openGeneration) return;
            unawaited(_selectPreferredAudio(nextPlayer, generation));
          });

          // Listen before open(): it can report errors on startup.
          final openedAt = DateTime.now();
          _startupPlaying = false;
          playingSubscription = nextPlayer.stream.playing.listen((isPlaying) {
            if (!mounted || generation != _openGeneration) return;
            if (isPlaying && !_startupPlaying) {
              _startupPlaying = true;
              _playbackStartedAt = DateTime.now();
              final seconds = DateTime.now().difference(openedAt).inSeconds;
              addDebugLog(
                "Player: '${currentStream.label}' arrancó en ${seconds}s",
              );
              unawaited(
                metricsRepository.recordStartup(
                  _serverMediaKey,
                  DateTime.now().difference(openedAt).inMilliseconds,
                ),
              );
              startupTimer?.cancel();
              unawaited(serverHealthRepository.reportPlaying(
                _serverMediaKey, currentStream,
              ));
              _scheduleNextPreload();
            }
          });
          playerErrorSubscription = nextPlayer.stream.error.listen((message) {
            if (mounted && generation == _openGeneration) {
              unawaited(_recoverFromPlayerError(message));
            }
          });

          startupTimer = Timer(const Duration(seconds: 12), () {
            if (!mounted ||
                generation != _openGeneration ||
                failoverInProgress ||
                _startupPlaying) {
              return;
            }
            addDebugLog("Player: arranque agotado, probando otra fuente");
            unawaited(_autoFailover('No inició la señal después de 12s'));
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
                title: 'Audio alterno',
              ),
            );
          }
          if (!mounted || generation != _openGeneration) return;
          unawaited(_selectPreferredAudio(nextPlayer, generation));
          unawaited(_loadPreferredSubtitles(nextPlayer, generation));
          if (effectiveResumeAt != null &&
              effectiveResumeAt > Duration.zero) {
            await nextPlayer.seek(effectiveResumeAt);
          }
          final finalStreamLog = 'Resolver: URL final del stream -> ${safeMediaUrlForLog(currentStream.uri)}';
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
          final finalStreamLog = 'Resolver: URL final del stream -> ${safeMediaUrlForLog(currentStream.uri)}';
          debugPrint(finalStreamLog);
          addDebugLog(finalStreamLog);
        }

        break;
      } catch (error, stack) {
        if (!mounted || generation != _openGeneration) return;
        unawaited(serverHealthRepository.reportError(
          _serverMediaKey, currentStream,
        ));
        final errorLog = 'Resolver error: ${safePlaybackErrorForLog(error.toString())}';
        final stackLog = 'Resolver stack: $stack';
        debugPrint(errorLog);
        debugPrint(stackLog);
        addDebugLog(errorLog);
        addDebugLog(stackLog);

        await playerErrorSubscription?.cancel();
        playerErrorSubscription = null;
        await player?.dispose();
        player = null;
        videoController = null;

        if (currentIndex + 1 < widget.session.candidates.length) {
          currentIndex += 1;
          continue;
        }

        playbackError = safePlaybackErrorForLog(error.toString());
        break;
      }
    }

    if (mounted &&
        (notify || playbackError != null || media3ResumeAt != null)) {
      setState(() {});
    }
  }

  void _scheduleNextPreload() {
    nextPreloadTimer?.cancel();
    if (!playerPreferences.autoplayNext || widget.session.autoplayQueue.isEmpty) {
      return;
    }
    nextPreloadTimer = Timer(const Duration(seconds: 8), () {
      if (!mounted) return;
      final next = widget.session.autoplayQueue.first;
      unawaited(
        ref
            .read(playbackPreparationServiceProvider)
            .prepare(PlaybackPreparationRequest.fromContext(next)),
      );
    });
  }

  Future<void> _autoplayNextEpisode() async {
    if (_advancingEpisode ||
        !mounted ||
        !playerPreferences.autoplayNext ||
        widget.session.autoplayQueue.isEmpty) {
      return;
    }
    _advancingEpisode = true;
    try {
      final next = widget.session.autoplayQueue.first;
      final prepared = await ref
          .read(playbackPreparationServiceProvider)
          .prepare(PlaybackPreparationRequest.fromContext(next));
      if (!mounted || prepared.candidates.isEmpty) return;

      final title = next.mediaType == 'tv'
          ? next.title +
              ' · T' +
              (next.season ?? 1).toString() +
              ' E' +
              (next.episode ?? 1).toString()
          : next.title + ' · E' + (next.episode ?? 1).toString();

      context.pushReplacement(
        '/player',
        extra: PlaybackSession(
          title: title,
          candidates: prepared.candidates,
          playbackContext: next,
          subtitles: prepared.subtitles,
          autoplayQueue:
              widget.session.autoplayQueue.skip(1).toList(growable: false),
        ),
      );
    } catch (_) {
      addDebugLog('Player: no se pudo preparar el siguiente episodio');
    } finally {
      _advancingEpisode = false;
    }
  }

  Duration? get _currentPosition {
    final p = player;
    if (p != null) return p.state.position;
    final state = media3State;
    if (state != null) return Duration(milliseconds: state.positionMs);
    return media3ResumeAt;
  }

  void _attachMedia3Controller(Media3PlayerController controller) {
    media3Controller?.dispose();
    media3Controller = controller;
    controller.setHandlers(
      onLog: (message) {
        if (message.isNotEmpty) addDebugLog(message);
      },
      onError: (message) {
        if (mounted) unawaited(_recoverFromPlayerError(message));
      },
      onStarted: (startupMs) {
        if (!mounted) return;
        _startupPlaying = true;
        _playbackStartedAt = DateTime.now();
        startupTimer?.cancel();
        addDebugLog(
          'Player: reproducción nativa iniciada en ' +
              startupMs.toString() +
              'ms',
        );
        unawaited(metricsRepository.recordStartup(_serverMediaKey, startupMs));
        unawaited(
          serverHealthRepository.reportPlaying(
            _serverMediaKey,
            currentStream,
          ),
        );
        _scheduleNextPreload();
      },
      onEnded: () {
        addDebugLog('Player: contenido finalizado');
        unawaited(_autoplayNextEpisode());
      },
    );

    startupTimer?.cancel();
    startupTimer = Timer(const Duration(seconds: 12), () {
      if (!mounted ||
          failoverInProgress ||
          _startupPlaying ||
          media3Controller != controller) {
        return;
      }
      unawaited(_autoFailover('La señal no inició a tiempo'));
    });

    media3StateTimer?.cancel();
    media3StateTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(_refreshMedia3State(controller)),
    );
    unawaited(_refreshMedia3State(controller));
  }

  Future<void> _refreshMedia3State(Media3PlayerController controller) async {
    try {
      final state = await controller.state();
      if (!mounted || state == null || media3Controller != controller) return;
      setState(() => media3State = state);
    } catch (_) {
      // State polling is only for controls/history; playback continues.
    }
  }

  /// Recover a stream interruption twice on the same source; after the
  /// third consecutive interruption, move on to the next server. A playback
  /// that remained healthy for over one minute clears the prior interruption
  /// count. Subtitle-only errors are not video-server failures.
  Future<void> _recoverFromPlayerError(String message) async {
    if (!mounted || failoverInProgress || _handlingPlaybackError) return;
    _handlingPlaybackError = true;
    try {
    final error = message.toLowerCase();
    if ((error.contains('subtitle') || error.contains('subtítulo')) &&
        !error.contains('video') && !error.contains('demux')) {
      addDebugLog('Player: problema aislado de subtítulos');
      return;
    }
    final startedAt = _playbackStartedAt;
    if (_startupPlaying &&
        startedAt != null &&
        DateTime.now().difference(startedAt) >=
            const Duration(minutes: 1)) {
      _consecutiveInterruptions = 0;
    }
    await serverHealthRepository.reportError(_serverMediaKey, currentStream);
    if (!mounted || failoverInProgress) return;
    if (_startupPlaying && _consecutiveInterruptions < 2) {
      _consecutiveInterruptions++;
      failoverInProgress = true;
      final resumeAt = widget.session.isLive ? null : _currentPosition;
      addDebugLog('Player: recuperando fuente ${_consecutiveInterruptions}/2');
      try {
        await _openCurrent(resumeAt: resumeAt);
      } finally {
        failoverInProgress = false;
      }
      return;
    }
    await _autoFailover(message, reportFailure: false);
    } finally {
      _handlingPlaybackError = false;
    }
  }

  Future<void> _autoFailover(
    String message, {
    bool reportFailure = true,
  }) async {
    if (!mounted || failoverInProgress) return;
    if (reportFailure) {
      unawaited(serverHealthRepository.reportError(
        _serverMediaKey, currentStream,
      ));
    }
    unawaited(metricsRepository.recordFailure(_serverMediaKey));
    if (currentIndex + 1 >= widget.session.candidates.length) {
      setState(() => playbackError = safePlaybackErrorForLog(message));
      return;
    }

    failoverInProgress = true;
    _consecutiveInterruptions = 0;
    final resumeAt = _currentPosition;
    final failed = currentStream.label;
    currentIndex += 1;
    addDebugLog('Player: ${safePlaybackErrorForLog(failed)} falló; probando ${safePlaybackErrorForLog(currentStream.label)}');

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 2),
          content: Text(
            'Problema con la señal. Probando otra opción…',
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
      const Duration(seconds: 15),
      (_) => unawaited(_saveProgress()),
    );
  }

  Future<void> _saveProgress() async {
    final playbackContext = widget.session.playbackContext;
    if (playbackContext == null) return;

    final p = player;
    final nativeState = media3State;
    final position = p?.state.position ??
        (nativeState == null
            ? Duration.zero
            : Duration(milliseconds: nativeState.positionMs));
    final duration = p?.state.duration ??
        (nativeState == null
            ? Duration.zero
            : Duration(milliseconds: nativeState.durationMs));
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

  void _exitPlayer() {
    if (!mounted) return;
    // pop() rather than maybePop(): route-local navigator pop handlers
    // sometimes report 'handled' without actually leaving the player.
    // Always provide a deterministic return path for the in-player arrow.
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      context.go('/');
    }
  }

  Future<void> _switchServer(int index) async {
    if (index == currentIndex) {
      if (mounted) Navigator.of(context).pop();
      return;
    }

    final resumeAt = _currentPosition;
    if (mounted) Navigator.of(context).pop();
    currentIndex = index;
    _consecutiveInterruptions = 0;
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

  Future<void> _showAudioTracks() async {
    final native = media3Controller;
    if (native != null) {
      final tracks = await native.audioTracks();
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: const Color(0xFF0D1418),
        builder: (context) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(title: Text('Audio')),
              for (final track in tracks.where((value) => value.supported))
                ListTile(
                  leading: Icon(
                    track.selected
                        ? Icons.check_circle
                        : Icons.circle_outlined,
                  ),
                  title: Text(track.displayName),
                  onTap: () {
                    unawaited(native.selectAudio(track));
                    Navigator.of(context).pop();
                  },
                ),
            ],
          ),
        ),
      );
      return;
    }

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
                  p.setAudioTrack(track);
                  Navigator.of(context).pop();
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectPreferredAudio(Player target, int generation) async {
    if (_audioAutoSelected ||
        !mounted ||
        generation != _openGeneration ||
        currentStream.externalAudioUri != null) return;
    final preferred = _languageSelector.preferredAudio(
      target.state.tracks.audio,
      preferredLanguage: playerPreferences.audioLanguage,
    );
    if (preferred == null) return;
    _audioAutoSelected = true;
    try {
      await target.setAudioTrack(preferred);
    } catch (_) {
      // Metadata can disappear during stream failover. Retain default audio.
    }
  }

  Future<void> _loadPreferredSubtitles(Player target, int generation) async {
    final media = widget.session.playbackContext;
    if (media == null ||
        widget.session.isLive ||
        playerPreferences.subtitleLanguage.toLowerCase() == 'off') {
      return;
    }
    List<StremioSubtitle> available;
    try {
      available = await StremioSubtitleService(
        StremioAddonRepository(),
        Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
        )),
      ).forPlayback(media);
    } catch (_) {
      return;
    }
    if (!mounted || generation != _openGeneration) return;
    setState(() => _externalSubtitleOptions = available);
    // Audio and embedded subtitle tracks may arrive after open().
    await Future<void>.delayed(const Duration(milliseconds: 650));
    if (!mounted || generation != _openGeneration || _subtitleUserSelected ||
        _subtitleAutoSelected) return;
    await _selectPreferredAudio(target, generation);
    final audio = target.state.track.audio;
    if (_languageSelector.isSpanishAudio(
      track: audio,
      streamLanguage: currentStream.language,
    )) {
      return; // Latino dubbing wins; don't cover it with unwanted subtitles.
    }
    final embedded = _languageSelector.preferredEmbeddedSubtitle(
      target.state.tracks.subtitle,
    );
    final external = available.where((item) => item.isSpanish);
    try {
      if (embedded != null) {
        _subtitleAutoSelected = true;
        await target.setSubtitleTrack(embedded);
      } else if (external.isNotEmpty) {
        _subtitleAutoSelected = true;
        final subtitle = external.first;
        await target.setSubtitleTrack(SubtitleTrack.uri(
          subtitle.url.toString(),
          title: subtitle.label,
          language: subtitle.language,
        ));
      }
    } catch (_) {
      // Subtitle delivery should never interrupt video playback.
    }
  }

  Future<void> _showSubtitleTracks() async {
    final native = media3Controller;
    if (native != null) {
      final tracks = await native.subtitleTracks();
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: const Color(0xFF0D1418),
        builder: (context) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                leading: const Icon(Icons.subtitles_off_rounded),
                title: const Text('Desactivados'),
                onTap: () {
                  unawaited(native.disableSubtitles());
                  Navigator.of(context).pop();
                },
              ),
              for (final track in tracks.where((value) => value.supported))
                ListTile(
                  leading: Icon(
                    track.selected
                        ? Icons.check_circle
                        : Icons.closed_caption_rounded,
                  ),
                  title: Text(track.displayName),
                  onTap: () {
                    unawaited(native.selectSubtitle(track));
                    Navigator.of(context).pop();
                  },
                ),
            ],
          ),
        ),
      );
      return;
    }

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
                  _subtitleUserSelected = true;
                  p.setSubtitleTrack(track);
                  Navigator.of(context).pop();
                },
              ),
            for (final subtitle in _externalSubtitleOptions)
              ListTile(
                leading: const Icon(Icons.closed_caption_rounded),
                title: Text(subtitle.isSpanish
                    ? 'Español · ${subtitle.label}'
                    : subtitle.label),
                onTap: () {
                  _subtitleUserSelected = true;
                  p.setSubtitleTrack(SubtitleTrack.uri(
                    subtitle.url.toString(),
                    title: subtitle.label,
                    language: subtitle.language,
                  ));
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

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    _showControls();

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack) {
      _exitPlayer();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.mediaPlayPause ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter) {
      final native = media3Controller;
      if (native != null) {
        unawaited(native.playPause());
      } else {
        player?.playOrPause();
      }
      return KeyEventResult.handled;
    }

    final native = media3Controller;
    final nativeState = media3State;
    if (native != null && nativeState != null &&
        key == LogicalKeyboardKey.arrowLeft) {
      final target =
          Duration(milliseconds: nativeState.positionMs) -
          const Duration(seconds: 10);
      unawaited(native.seekTo(target.isNegative ? Duration.zero : target));
      return KeyEventResult.handled;
    }
    if (native != null && nativeState != null &&
        key == LogicalKeyboardKey.arrowRight) {
      unawaited(
        native.seekTo(
          Duration(milliseconds: nativeState.positionMs + 10000),
        ),
      );
      return KeyEventResult.handled;
    }

    final p = player;
    if (p != null && key == LogicalKeyboardKey.arrowLeft) {
      final target = p.state.position - const Duration(seconds: 10);
      p.seek(target.isNegative ? Duration.zero : target);
      return KeyEventResult.handled;
    }
    if (p != null && key == LogicalKeyboardKey.arrowRight) {
      p.seek(p.state.position + const Duration(seconds: 10));
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
        message: 'Esta señal no respondió. Puedes reintentar o probar otra opción.',
        hasAlternatives: widget.session.candidates.length > 1,
        onRetry: () {
          currentIndex = 0;
          unawaited(_openCurrent());
        },
        onServers: _showServers,
      );
    } else {
      content = switch (currentStream.backend) {
        PlaybackBackend.native => Platform.isAndroid
            ? (!preferencesLoaded || !media3Ready
                ? const Center(child: CircularProgressIndicator())
                : Media3PlayerSurface(
                    key: ValueKey('media3-' + currentStream.id),
                    stream: currentStream,
                    title: widget.session.title,
                    resumeAt: media3ResumeAt,
                    audioPreference: playerPreferences.media3AudioPreference,
                    subtitlePreference:
                        playerPreferences.media3SubtitlePreference,
                    subtitles: widget.session.subtitles,
                    onController: _attachMedia3Controller,
                  ))
            : (videoController == null
                ? const Center(child: CircularProgressIndicator())
                : Video(
                    controller: videoController!,
                    controls: NoVideoControls,
                    fit: BoxFit.contain,
                  )),
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
                    media3State: media3State,
                    isLive: widget.session.isLive,
                    onBack: _exitPlayer,
                    onAudio: (p == null && media3Controller == null)
                        ? null
                        : _showAudioTracks,
                    onSubtitles: (p == null && media3Controller == null)
                        ? null
                        : _showSubtitleTracks,
                    onQuality: p == null ? null : _showVideoTracks,
                    onMedia3PlayPause: media3Controller == null
                        ? null
                        : () => unawaited(media3Controller!.playPause()),
                    onMedia3Seek: media3Controller == null
                        ? null
                        : (position) =>
                            unawaited(media3Controller!.seekTo(position)),
                    onCast: media3Controller == null
                        ? null
                        : () => unawaited(media3Controller!.toggleCast()),
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
                'Este contenido sólo puede abrirse fuera de POTV.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () => onOpen(),
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Continuar'),
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
                'No se pudo reproducir el contenido',
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
                      label: const Text('Otras opciones'),
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
  final Media3PlayerState? media3State;
  final bool isLive;
  final VoidCallback onBack;
  final VoidCallback? onAudio;
  final VoidCallback? onSubtitles;
  final VoidCallback? onQuality;
  final VoidCallback? onMedia3PlayPause;
  final ValueChanged<Duration>? onMedia3Seek;
  final VoidCallback? onCast;
  final VoidCallback onServers;

  const _PlayerOverlay({
    required this.title,
    required this.stream,
    required this.player,
    required this.media3State,
    required this.isLive,
    required this.onBack,
    required this.onAudio,
    required this.onSubtitles,
    required this.onQuality,
    required this.onMedia3PlayPause,
    required this.onMedia3Seek,
    required this.onCast,
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
              )
            else if (media3State != null && onMedia3PlayPause != null)
              IconButton.filled(
                iconSize: 42,
                onPressed: onMedia3PlayPause,
                icon: Icon(
                  media3State!.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                ),
              ),
            const Spacer(),
            if (player != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: _Timeline(player: player!, isLive: isLive),
              )
            else if (media3State != null && onMedia3Seek != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: _Media3Timeline(
                  state: media3State!,
                  isLive: isLive,
                  onSeek: onMedia3Seek!,
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
              child: Column(
                children: [
                  if (stream.language != null || stream.quality != null) ...[
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
                  ],
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
                      if (onCast != null)
                        _ActionButton(
                          icon: Icons.cast_rounded,
                          label: media3State?.isCasting == true
                              ? 'Transmitiendo'
                              : 'Enviar a TV',
                          onPressed: onCast,
                        ),
                      _ActionButton(
                        icon: Icons.dns_outlined,
                        label: 'Cambiar señal',
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

class _Media3Timeline extends StatelessWidget {
  final Media3PlayerState state;
  final bool isLive;
  final ValueChanged<Duration> onSeek;

  const _Media3Timeline({
    required this.state,
    required this.isLive,
    required this.onSeek,
  });

  String _format(Duration value) {
    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final duration = Duration(milliseconds: state.durationMs);
    final position = Duration(milliseconds: state.positionMs);
    final max = state.durationMs <= 0 ? 1.0 : state.durationMs.toDouble();
    final value = state.positionMs
        .clamp(0, state.durationMs <= 0 ? 0 : state.durationMs)
        .toDouble();
    return Row(
      children: [
        Text(_format(position)),
        Expanded(
          child: Slider(
            min: 0,
            max: max,
            value: value.clamp(0, max),
            onChanged: state.durationMs <= 0
                ? null
                : (next) =>
                    onSeek(Duration(milliseconds: next.round())),
          ),
        ),
        Text(
          state.durationMs <= 0
              ? (isLive ? 'EN VIVO' : '--:--')
              : _format(duration),
        ),
      ],
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
