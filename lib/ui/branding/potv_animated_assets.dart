import 'dart:async';

import 'package:flutter/material.dart';

/// Shared artwork for the startup and playback buffering states.
///
/// Both files are animated WebP assets with a transparent alpha channel.
abstract final class PotvAnimatedAssets {
  static const String startup = 'assets/branding/POTV_inicio_animado_transparente.webp';
  static const String buffering = 'assets/branding/POTV_loader_animado_transparente.webp';
}

/// Shown once per app launch, after Flutter renders its first frame.
/// Does not require an account and never blocks the bootstrap process.
class PotvStartupSplash extends StatefulWidget {
  const PotvStartupSplash({super.key, required this.child});

  final Widget child;

  @override
  State<PotvStartupSplash> createState() => _PotvStartupSplashState();
}

class _PotvStartupSplashState extends State<PotvStartupSplash> {
  Timer? _timer;
  bool _showSplash = true;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 2700), () {
      if (mounted) setState(() => _showSplash = false);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_showSplash) return widget.child;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: Colors.black,
        child: Center(
          child: Semantics(
            label: 'POTV iniciando',
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Image.asset(
                  PotvAnimatedAssets.startup,
                  fit: BoxFit.contain,
                  cacheWidth: 760,
                  filterQuality: FilterQuality.medium,
                  gaplessPlayback: true,
                  excludeFromSemantics: true,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Transparent animated flag on top of an existing black player background.
/// No animation controller is needed: Flutter's image codec plays the WebP.
class PotvBufferingFlag extends StatelessWidget {
  const PotvBufferingFlag({super.key, this.width = 180});

  final double width;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Cargando reproducción',
      child: Center(
        child: SizedBox(
          width: width,
          height: width * 2 / 3,
          child: Image.asset(
            PotvAnimatedAssets.buffering,
            fit: BoxFit.contain,
            cacheWidth: 360,
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
            excludeFromSemantics: true,
          ),
        ),
      ),
    );
  }
}
