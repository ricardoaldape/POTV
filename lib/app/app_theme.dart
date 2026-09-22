import 'package:flutter/material.dart';

class PotvTheme {
  static const background = Color(0xFF05090D);
  static const surface = Color(0xFF0D151B);
  static const surfaceAlt = Color(0xFF13232C);
  static const cyan = Color(0xFF4BE8F4);
  static const cyanDeep = Color(0xFF10BFD1);
  static const mint = Color(0xFF65E6B4);
  static const warm = Color(0xFFFFB45E);

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: cyan,
      brightness: Brightness.dark,
      surface: surface,
    ).copyWith(
      primary: cyan,
      secondary: mint,
      tertiary: warm,
      surface: surface,
    );

    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      colorScheme: scheme,
      useMaterial3: true,
      cardTheme: CardThemeData(
        color: surface,
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: Colors.white.withValues(alpha: 0.06),
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: const Color(0xFF071016),
        indicatorColor: cyan.withValues(alpha: 0.16),
        selectedIconTheme: const IconThemeData(
          color: cyan,
          size: 26,
        ),
        unselectedIconTheme: const IconThemeData(
          color: Colors.white60,
          size: 24,
        ),
        selectedLabelTextStyle: const TextStyle(
          color: cyan,
          fontWeight: FontWeight.w800,
        ),
        unselectedLabelTextStyle: const TextStyle(
          color: Colors.white60,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xFF071016),
        indicatorColor: cyan.withValues(alpha: 0.16),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? cyan
                : Colors.white60,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: states.contains(WidgetState.selected)
                ? cyan
                : Colors.white60,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w800
                : FontWeight.w500,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(
            color: cyan,
            width: 1.5,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          foregroundColor: background,
          backgroundColor: cyan,
          padding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 14,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      focusColor: cyan.withValues(alpha: 0.20),
      splashColor: cyan.withValues(alpha: 0.12),
    );
  }
}
