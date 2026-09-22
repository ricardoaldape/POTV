import 'package:flutter/material.dart';

class PotvTheme {
  static const background = Color(0xFF070B0D);
  static const surface = Color(0xFF10171C);
  static const surfaceAlt = Color(0xFF162128);
  static const cyan = Color(0xFF33D7F1);
  static const mint = Color(0xFF46E7B0);

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: cyan,
      brightness: Brightness.dark,
      surface: surface,
    );
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      colorScheme: scheme,
      useMaterial3: true,
      cardTheme: const CardThemeData(
        color: surface,
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
      ),
      focusColor: cyan.withValues(alpha: 0.18),
      splashColor: cyan.withValues(alpha: 0.12),
    );
  }
}
