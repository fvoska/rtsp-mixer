import 'package:flutter/material.dart';

/// The app's three vendored families and the [TextTheme] built on top of them.
///
/// Outfit carries the display/headline voice, Nunito Sans does the UI work,
/// and Roboto Mono handles every numeric readout with tabular figures so a
/// ticking uptime does not shuffle sideways as digit widths change.
///
/// All three ship as TTFs in `assets/fonts/` (see
/// `tool/branding/verify_fonts.py`). Nothing here touches the network.
abstract final class AppTypography {
  static const display = 'Outfit';
  static const ui = 'Nunito Sans';
  static const mono = 'Roboto Mono';

  /// Roboto Mono with tabular figures — the shared numeric style. Every digit
  /// occupies the same advance width, so `6h 9m` -> `6h 10m` does not jitter.
  static const numeric = TextStyle(
    fontFamily: mono,
    fontWeight: FontWeight.w400,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// Numeric style for dense readouts (debug rows, inline counters).
  static const numericSmall = TextStyle(
    fontFamily: mono,
    fontWeight: FontWeight.w400,
    fontSize: 11,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// Numeric style for the figures a parent reads across the room.
  static const numericLarge = TextStyle(
    fontFamily: mono,
    fontWeight: FontWeight.w500,
    fontSize: 22,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// Re-cut an existing [TextStyle] as a tabular numeric one, keeping its size,
  /// colour, and line height. Use this when a readout should inherit a
  /// TextTheme role (`titleLarge`, `bodySmall`, …) but must not jitter.
  static TextStyle? tabular(TextStyle? base) => base?.copyWith(
        fontFamily: mono,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  /// Build the [TextTheme] for [brightness] on top of the Material 2021 base,
  /// so sizes, line heights, and per-brightness colours stay stock and only
  /// the families and weights change.
  static TextTheme textTheme(Brightness brightness) {
    final base = brightness == Brightness.dark
        ? Typography.material2021().white
        : Typography.material2021().black;

    TextStyle? outfit(TextStyle? s) =>
        s?.copyWith(fontFamily: display, fontWeight: FontWeight.w600);

    TextStyle? nunito(TextStyle? s, FontWeight weight) =>
        s?.copyWith(fontFamily: ui, fontWeight: weight);

    return base.copyWith(
      // Screen titles and hero figures.
      displayLarge: outfit(base.displayLarge),
      displayMedium: outfit(base.displayMedium),
      displaySmall: outfit(base.displaySmall),
      headlineLarge: outfit(base.headlineLarge),
      headlineMedium: outfit(base.headlineMedium),
      headlineSmall: outfit(base.headlineSmall),
      // Section and control titles.
      titleLarge: nunito(base.titleLarge, FontWeight.w600),
      titleMedium: nunito(base.titleMedium, FontWeight.w600),
      titleSmall: nunito(base.titleSmall, FontWeight.w600),
      // Running text.
      bodyLarge: nunito(base.bodyLarge, FontWeight.w400),
      bodyMedium: nunito(base.bodyMedium, FontWeight.w400),
      bodySmall: nunito(base.bodySmall, FontWeight.w400),
      // Buttons, chips, overlines.
      labelLarge: nunito(base.labelLarge, FontWeight.w600),
      labelMedium: nunito(base.labelMedium, FontWeight.w600),
      labelSmall: nunito(base.labelSmall, FontWeight.w600),
    );
  }
}
