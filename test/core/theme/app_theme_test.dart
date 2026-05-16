import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rtsp_mixer/core/theme/app_theme.dart';

void main() {
  group('AppTheme.dark appBarTheme', () {
    // These overrides exist to prevent the Material3 scrolled-under tint from
    // making the same AppBar render as two different shades depending on
    // whether the content scrolls under it. The user reported this as
    // "different background in header" — pinning the theme is the fix.

    final appBar = AppTheme.dark.appBarTheme;

    test('background pinned to surface (no tint variance)', () {
      expect(appBar.backgroundColor, isNotNull);
      expect(appBar.backgroundColor, AppTheme.dark.colorScheme.surface);
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
      expect(appBar.foregroundColor, AppTheme.dark.colorScheme.onSurface);
    });

    test('centerTitle is false (left-aligned across all screens)', () {
      expect(appBar.centerTitle, isFalse);
    });
  });
}
