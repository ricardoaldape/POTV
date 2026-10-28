import 'package:flutter/material.dart';

/// Shared POTV player indicator: actual transparent animated pirate flag.
/// All player engines use this widget. It does not need a network connection
/// and never delegates the loading chrome to an embedded provider.
class PotvPlayerLoader extends StatelessWidget {
  final double size;
  const PotvPlayerLoader({super.key, this.size = 120});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'POTV preparando reproducción',
      child: SizedBox(
        width: size,
        height: size * (2 / 3),
        child: Image.asset(
          'assets/branding/POTV_loader_animado_transparente.webp',
          fit: BoxFit.contain,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
          excludeFromSemantics: true,
        ),
      ),
    );
  }
}
