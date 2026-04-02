import 'package:flutter/material.dart';

abstract final class AppTheme {
  static const statusOnline = Color(0xFF81C784);
  static const statusOffline = Color(0xFFE57373);

  static final dark = ThemeData(
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF5C6BC0),
      brightness: Brightness.dark,
    ),
    useMaterial3: true,
  );
}
