import 'package:flutter/material.dart';

abstract final class AppTheme {
  static const statusOnline = Color(0xFF81C784);
  static const statusOffline = Color(0xFFE57373);

  static final dark = _buildDark();

  static ThemeData _buildDark() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF5C6BC0),
      brightness: Brightness.dark,
    );
    return ThemeData(
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      useMaterial3: true,
      // Pin AppBar appearance so the M3 scrolled-under tint can't make the
      // same bar render in two different shades depending on scroll state.
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: false,
      ),
    );
  }
}
