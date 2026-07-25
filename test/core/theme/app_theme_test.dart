import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rtsp_mixer/core/theme/app_theme.dart';

void main() {
  // Both brightnesses are asserted: the pinning below is the fix for a real
  // reported defect, and a light theme added later must not silently reopen it.
  final themes = <String, ThemeData>{
    'AppTheme.dark': AppTheme.dark,
    'AppTheme.light': AppTheme.light,
    'AppTheme.darkOled': AppTheme.darkOled,
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

  group('AppTheme.darkOled', () {
    final oled = AppTheme.darkOled;

    test('is a dark theme', () {
      expect(oled.brightness, Brightness.dark);
      expect(oled.colorScheme.brightness, Brightness.dark);
    });

    test('the two largest always-on areas are true black', () {
      // The whole point of the mode: an OLED pixel at #000000 draws no current.
      // If either of these drifts off pure black the feature stops paying for
      // itself.
      expect(oled.scaffoldBackgroundColor, const Color(0xFF000000));
      expect(oled.canvasColor, const Color(0xFF000000));
      expect(
        oled.navigationBarTheme.backgroundColor,
        const Color(0xFF000000),
      );
      expect(oled.colorScheme.surfaceContainerLowest, const Color(0xFF000000));
    });

    test('every background layer is darker than standard dark', () {
      final standard = AppTheme.dark;
      final pairs = <String, (Color, Color)>{
        'ground': (
          oled.scaffoldBackgroundColor,
          standard.scaffoldBackgroundColor
        ),
        'surface': (oled.colorScheme.surface, standard.colorScheme.surface),
        'inset': (
          oled.colorScheme.surfaceContainerHighest,
          standard.colorScheme.surfaceContainerHighest,
        ),
        'nav': (
          oled.navigationBarTheme.backgroundColor!,
          standard.navigationBarTheme.backgroundColor!,
        ),
      };
      pairs.forEach((name, colors) {
        expect(
          colors.$1.computeLuminance(),
          lessThan(colors.$2.computeLuminance()),
          reason: '$name should emit less light than in standard dark',
        );
      });
    });

    test('text and accents are shared with standard dark, not re-derived', () {
      // Only the surface family is re-grounded; the brand accents and every
      // `on*` pairing must stay identical so the OLED variant cannot drift.
      final standard = AppTheme.dark.colorScheme;
      expect(oled.colorScheme.primary, standard.primary);
      expect(oled.colorScheme.onSurface, standard.onSurface);
      expect(oled.colorScheme.onSurfaceVariant, standard.onSurfaceVariant);
      expect(oled.colorScheme.error, standard.error);
      expect(oled.colorScheme.tertiary, standard.tertiary);
    });

    test('body text still clears 7:1 against the black ground', () {
      // Contrast is the thing most easily lost when the ground moves; a parent
      // reading a camera name half-asleep is the reason it matters.
      final ratio = _contrast(
        oled.colorScheme.onSurface,
        oled.scaffoldBackgroundColor,
      );
      expect(ratio, greaterThan(7.0));
    });

    test('the hairline stays visible against the black ground', () {
      // A divider that vanishes into #000000 would erase the layout's structure.
      expect(
        _contrast(oled.dividerColor, oled.scaffoldBackgroundColor),
        greaterThan(1.15),
      );
    });

    test('darkFor selects the variant, leaving light untouched', () {
      expect(AppTheme.darkFor(oled: true), same(AppTheme.darkOled));
      expect(AppTheme.darkFor(oled: false), same(AppTheme.dark));
      // OLED is a dark-only concern — the light theme must be unaffected.
      expect(AppTheme.light.scaffoldBackgroundColor,
          isNot(const Color(0xFF000000)));
    });
  });
}

/// WCAG relative-luminance contrast ratio between two opaque colours.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}
