import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rtsp_mixer/core/theme/app_theme.dart';

/// The OLED preference is applied by swapping `MaterialApp.darkTheme`, which
/// only satisfies the requirement — "respected when dark mode is set by the OS
/// *or* explicitly in app settings" — if `darkTheme` really is what Flutter
/// picks in both cases. These tests pin that resolution end to end, using the
/// same wiring as `lib/app.dart`, so a future refactor that reaches for
/// `ThemeMode` instead fails here.
void main() {
  /// Renders the app's theme wiring under an OS brightness and captures the
  /// [ThemeData] the widget tree actually resolves to.
  Future<ThemeData> resolve(
    WidgetTester tester, {
    required Brightness platformBrightness,
    required ThemeMode themeMode,
    required bool oledDark,
  }) async {
    tester.platformDispatcher.platformBrightnessTestValue = platformBrightness;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    late ThemeData resolved;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.darkFor(oled: oledDark),
        themeMode: themeMode,
        home: Builder(
          builder: (context) {
            resolved = Theme.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    return resolved;
  }

  const black = Color(0xFF000000);

  testWidgets('OS-resolved dark (ThemeMode.system) honours the OLED toggle',
      (tester) async {
    final theme = await resolve(
      tester,
      platformBrightness: Brightness.dark,
      themeMode: ThemeMode.system,
      oledDark: true,
    );
    expect(theme.brightness, Brightness.dark);
    expect(theme.scaffoldBackgroundColor, black);
  });

  testWidgets('explicitly-chosen dark honours the OLED toggle',
      (tester) async {
    // Deliberately with a LIGHT OS brightness: an explicit Dark choice must not
    // depend on the platform agreeing.
    final theme = await resolve(
      tester,
      platformBrightness: Brightness.light,
      themeMode: ThemeMode.dark,
      oledDark: true,
    );
    expect(theme.brightness, Brightness.dark);
    expect(theme.scaffoldBackgroundColor, black);
  });

  testWidgets('dark with the toggle off keeps the standard petrol ground',
      (tester) async {
    for (final mode in [ThemeMode.system, ThemeMode.dark]) {
      final theme = await resolve(
        tester,
        platformBrightness: Brightness.dark,
        themeMode: mode,
        oledDark: false,
      );
      expect(theme.brightness, Brightness.dark, reason: '$mode');
      expect(
        theme.scaffoldBackgroundColor,
        AppTheme.dark.scaffoldBackgroundColor,
        reason: '$mode should use the standard dark ground',
      );
      expect(theme.scaffoldBackgroundColor, isNot(black), reason: '$mode');
    }
  });

  testWidgets('light stays light with the OLED toggle on', (tester) async {
    // Both ways of landing on light: explicit, and OS-resolved.
    for (final entry in {
      ThemeMode.light: Brightness.dark,
      ThemeMode.system: Brightness.light,
    }.entries) {
      final theme = await resolve(
        tester,
        platformBrightness: entry.value,
        themeMode: entry.key,
        oledDark: true,
      );
      expect(theme.brightness, Brightness.light, reason: '${entry.key}');
      expect(
        theme.scaffoldBackgroundColor,
        AppTheme.light.scaffoldBackgroundColor,
        reason: '${entry.key} must be untouched by the OLED preference',
      );
    }
  });
}
