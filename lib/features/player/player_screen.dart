import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../domain/models/stream_candidate.dart';
import 'secure_webview_player.dart';

class PlayerScreen extends StatefulWidget {
  final StreamCandidate stream;

  const PlayerScreen({
    super.key,
    required this.stream,
  });

  factory PlayerScreen.fromExtra(Object? extra) {
    if (extra is StreamCandidate) {
      return PlayerScreen(stream: extra);
    }

    return PlayerScreen(
      stream: StreamCandidate(
        id: 'invalid',
        label: 'Fuente no disponible',
        uri: Uri.parse('https://example.invalid'),
      ),
    );
  }

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  Player? player;
  VideoController? videoController;

  @override
  void initState() {
    super.initState();

    if (widget.stream.backend == PlaybackBackend.native) {
      final p = Player();
      player = p;
      videoController = VideoController(p);

      p.open(
        Media(
          widget.stream.uri.toString(),
          httpHeaders: widget.stream.headers,
        ),
        play: true,
      );
    }
  }

  @override
  void dispose() {
    player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = switch (widget.stream.backend) {
      PlaybackBackend.native => Video(controller: videoController!),
      PlaybackBackend.webView => SecureWebViewPlayer(stream: widget.stream),
      PlaybackBackend.external => const Center(
          child: Text('Reproductor externo: pendiente'),
        ),
    };

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          content,
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: IconButton.filledTonal(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
