import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../domain/models/playback_session.dart';
import '../../domain/models/stream_candidate.dart';
import 'secure_webview_player.dart';

class PlayerScreen extends StatefulWidget {
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
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  Player? player;
  VideoController? videoController;
  Timer? hideTimer;
  bool controlsVisible = true;
  late int currentIndex;

  StreamCandidate get currentStream =>
      widget.session.candidates[currentIndex];

  @override
  void initState() {
    super.initState();
    currentIndex = widget.session.initialIndex
        .clamp(0, widget.session.candidates.length - 1)
        .toInt();
    _openCurrent(notify: false);
    _armAutoHide();
  }

  @override
  void dispose() {
    hideTimer?.cancel();
    player?.dispose();
    super.dispose();
  }

  void _openCurrent({bool notify = true}) {
    player?.dispose();
    player = null;
    videoController = null;

    if (currentStream.backend == PlaybackBackend.native) {
      final nextPlayer = Player();
      player = nextPlayer;
      videoController = VideoController(nextPlayer);
      nextPlayer.open(
        Media(
          currentStream.uri.toString(),
          httpHeaders: currentStream.headers,
        ),
        play: true,
      );
    }

    if (notify && mounted) setState(() {});
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
    if (mounted) Navigator.of(context).pop();
    currentIndex = index;
    _openCurrent();
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
                'Servidores',
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
                title: Text(widget.session.candidates[i].label),
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
                  track.title ?? track.language ?? 'Pista ' + track.id,
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
                      : track.title ?? track.language ?? 'Pista ' + track.id,
                ),
                onTap: () {
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
                          ? 'Pista ' + track.id
                          : track.h.toString() + 'p'),
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
    if (key == LogicalKeyboardKey.mediaPlayPause ||
        key == LogicalKeyboardKey.space) {
      player?.playOrPause();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final p = player;

    final content = switch (currentStream.backend) {
      PlaybackBackend.native => Video(
          controller: videoController!,
          controls: NoVideoControls,
        ),
      PlaybackBackend.webView => SecureWebViewPlayer(
          key: ValueKey(currentStream.id),
          stream: currentStream,
        ),
      PlaybackBackend.external => const Center(
          child: Text('Reproductor externo: pendiente'),
        ),
    };

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
                    onBack: () => Navigator.of(context).maybePop(),
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

class _PlayerOverlay extends StatelessWidget {
  final String title;
  final StreamCandidate stream;
  final Player? player;
  final VoidCallback onBack;
  final VoidCallback? onAudio;
  final VoidCallback? onSubtitles;
  final VoidCallback? onQuality;
  final VoidCallback onServers;

  const _PlayerOverlay({
    required this.title,
    required this.stream,
    required this.player,
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
            Container(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: [
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
                  _ActionButton(
                    icon: Icons.high_quality,
                    label: 'Calidad',
                    onPressed: onQuality,
                  ),
                  _ActionButton(
                    icon: Icons.dns_outlined,
                    label: 'Servidores',
                    onPressed: onServers,
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
