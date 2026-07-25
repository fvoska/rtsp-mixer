import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rtsp_mixer/core/theme/app_theme.dart';

void main() {
  // Both brightnesses are asserted: the pinning below is the fix for a real
  // reported defect, and a light theme added later must not silently reopen it.
  final themes = <String, ThemeData>{
    'AppTheme.dark': AppTheme.dark,
    'AppTheme.light': AppTheme.light,
  };

  for (final entry in themes.entries) {
    group('${entry.key} appBarTheme', () {
      // These overrides exist to prevent the Material3 scrolled-under tint from
      // making the same AppBar render as two different shades depending on
      // whether the content scrolls under it. The user reported this as
      // "different background in header" — pinning the theme is the fix.

      final theme = entry.value;
      final appBar = theme.appBarTheme;

      test('background pinned to surface (no tint variance)', () {
        expect(appBar.backgroundColor, isNotNull);
        expect(appBar.backgroundColor, theme.colorScheme.surface);
      });

      test('surfaceTintColor is transparent', () {
        expect(appBar.surfaceTintColor, Colors.transparent);
      });

      test('scrolledUnderElevation is 0', () {
        expect(appBar.scrolledUnderElevation, 0);
      });

      test('base elevation is 0', () {
        expect(appBar.elevation, 0);
      });

      test('foregroundColor is onSurface', () {
        expect(appBar.foregroundColor, theme.colorScheme.onSurface);
      });

      test('centerTitle is false (left-aligned across all screens)', () {
        expect(appBar.centerTitle, isFalse);
      });
    });
  }

  group('AppTheme brightness', () {
    test('light theme is light, dark theme is dark', () {
      expect(AppTheme.light.brightness, Brightness.light);
      expect(AppTheme.light.colorScheme.brightness, Brightness.light);
      expect(AppTheme.dark.brightness, Brightness.dark);
      expect(AppTheme.dark.colorScheme.brightness, Brightness.dark);
    });

    test('cards sit one step off the ground, not on it', () {
      // Nightwatch stack: ground < card. If these collapse to the same colour
      // the cards stop reading as objects.
      for (final theme in themes.values) {
        expect(theme.cardTheme.color, theme.colorScheme.surface);
        expect(theme.cardTheme.color, isNot(theme.scaffoldBackgroundColor));
      }
    });

    test('dark bottom nav reads darker than the body', () {
      final nav = AppTheme.dark.navigationBarTheme.backgroundColor;
      expect(nav, isNotNull);
      expect(
        nav!.computeLuminance(),
        lessThan(AppTheme.dark.scaffoldBackgroundColor.computeLuminance()),
      );
    });
  });
}
