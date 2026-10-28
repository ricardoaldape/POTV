import 'dart:async';

import 'package:flutter/material.dart';

/// POTV permanent brand assets bundled into every APK, never network loaded.
abstract final class PotvAnimatedAssets {
  static const startup = 'assets/branding/POTV_inicio_animado_transparente.webp';
  static const loading = 'assets/branding/POTV_loader_animado_transparente.webp';
}

/// One per cold Flutter launch, independent of catalog/network availability.
/// Black background ensures the dark flag and cyan highlights remain legible.
class PotvStartupSplash extends StatefulWidget {
  const PotvStartupSplash({super.key, required this.child});
  final Widget child;
  @override
  State<PotvStartupSplash> createState() => _PotvStartupSplashState();
}

class _PotvStartupSplashState extends State<PotvStartupSplash> {
  Timer? _timer;
  bool _show = true;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 2700), () {
      if (mounted) setState(() => _show = false);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (_show)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black,
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(18),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: 760),
                      child: Image(
                        image: AssetImage(PotvAnimatedAssets.startup),
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                        filterQuality: FilterQuality.medium,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Automatically decodes each frame of the original transparent animated WebP.
/// A single reusable loading component for every app screen and playback engine.
class PotvLoadingFlag extends StatelessWidget {
  const PotvLoadingFlag({super.key, this.width = 120});

  final double width;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'POTV cargando',
      child: Center(
        child: SizedBox(
          width: width,
          height: width * (2 / 3),
          child: Image.asset(
            PotvAnimatedAssets.loading,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
            excludeFromSemantics: true,
          ),
        ),
      ),
    );
  }
}
