import 'package:flutter/material.dart';

abstract final class AppTheme {
  static const Color _seedColor = Color(0xFF5C6BC0);

  /// Status colors for camera online/offline indicators.
  static const Color statusOnline = Color(0xFF81C784);
  static const Color statusOffline = Color(0xFFE57373);

  static ThemeData get dark {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: Brightness.dark,
    );

    return ThemeData.dark(useMaterial3: true).copyWith(
      colorScheme: colorScheme,
      textTheme: ThemeData.dark(useMaterial3: true).textTheme.copyWith(
        bodyLarge: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          height: 1.5,
        ),
        labelLarge: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          height: 1.4,
        ),
        headlineMedium: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          height: 1.2,
        ),
        titleLarge: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          height: 1.3,
        ),
      ),
    );
  }
}
