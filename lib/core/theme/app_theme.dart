import 'package:flutter/material.dart';

import 'app_typography.dart';
import 'status_colors.dart';

/// The "Roomtone" palette: a petrol/teal identity built for a room that is
/// dark most of the time the app is open, and for a phone that a parent picks
/// up mid-sleep. Both brightnesses are authored explicitly rather than seeded,
/// so the ground/surface/inset separation is deliberate instead of whatever
/// tonal-palette maths produces.
abstract final class _Roomtone {
  // ---- Dark ----------------------------------------------------------
  static const darkGround = Color(0xFF0B1618); // scaffold / deepest layer
  static const darkSurface = Color(0xFF122224); // cards, sheets, app bar
  static const darkInset = Color(0xFF1A2E30); // wells, chips, inputs
  static const darkNav = Color(0xFF081113); // bottom bar, below the body
  static const darkInk = Color(0xFFE3EDEC);
  static const darkMuted = Color(0xFF93A7A7);
  static const darkHairline = Color(0xFF23393B);
  static const darkOutline = Color(0xFF3A5254);

  // ---- Dark (OLED) ---------------------------------------------------
  // An OLED panel draws no current for a fully black pixel, so the two
  // largest, always-on areas — the scaffold ground and the bottom bar — go to
  // true #000000. The layers above them stay *near*-black rather than black:
  // if a card collapsed onto the ground the Nightwatch stack would lose its
  // depth cues entirely, which is a worse trade than a few microwatts.
  static const oledGround = Color(0xFF000000);
  static const oledNav = Color(0xFF000000);
  static const oledSurface = Color(0xFF0A1213); // cards, sheets, app bar
  static const oledInset = Color(0xFF141F20); // wells, chips, inputs
  static const oledHairline = Color(0xFF1E2C2D);

  // ---- Light ---------------------------------------------------------
  static const lightGround = Color(0xFFEBF0EF);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightInset = Color(0xFFDDE6E5);
  static const lightNav = Color(0xFFFFFFFF);
  static const lightInk = Color(0xFF0F1F21);
  static const lightMuted = Color(0xFF4E6567);
  static const lightHairline = Color(0xFFCBD8D7);
  static const lightOutline = Color(0xFF7C9092);
}

abstract final class AppTheme {
  static final light = _build(Brightness.light);
  static final dark = _build(Brightness.dark);

  /// [dark] with every background layer pushed down to (near-)black, for
  /// minimal panel luminance on OLED screens overnight.
  static final darkOled = _build(Brightness.dark, oled: true);

  /// The dark theme to hand [MaterialApp.darkTheme].
  ///
  /// Selecting the variant here — rather than at each `Theme.of` call site —
  /// is what makes the OLED preference independent of *how* dark mode was
  /// reached: Flutter applies `darkTheme` both when the user picked
  /// [ThemeMode.dark] explicitly and when [ThemeMode.system] resolves dark
  /// from the OS, so a single swap covers both.
  static ThemeData darkFor({required bool oled}) => oled ? darkOled : dark;

  static ColorScheme _darkScheme() => const ColorScheme(
        brightness: Brightness.dark,
        primary: Color(0xFF3FBFAD),
        onPrimary: Color(0xFF00201C),
        primaryContainer: Color(0xFF17403C),
        onPrimaryContainer: Color(0xFFA9EDE3),
        secondary: Color(0xFF5FA8D3),
        onSecondary: Color(0xFF00243A),
        secondaryContainer: Color(0xFF17323F),
        onSecondaryContainer: Color(0xFFC7E4F5),
        tertiary: Color(0xFFE0A458), // warning amber, reserved for reconnecting
        onTertiary: Color(0xFF2E1C05),
        tertiaryContainer: Color(0xFF41300F),
        onTertiaryContainer: Color(0xFFF7DCB4),
        error: Color(0xFFE0715B),
        onError: Color(0xFF2E0A05),
        errorContainer: Color(0xFF4A1B12),
        onErrorContainer: Color(0xFFFFD8D0),
        surface: _Roomtone.darkSurface,
        onSurface: _Roomtone.darkInk,
        surfaceContainerLowest: _Roomtone.darkGround,
        surfaceContainerLow: Color(0xFF0F1D1F),
        surfaceContainer: Color(0xFF142527),
        surfaceContainerHigh: Color(0xFF17292B),
        surfaceContainerHighest: _Roomtone.darkInset,
        onSurfaceVariant: _Roomtone.darkMuted,
        outline: _Roomtone.darkOutline,
        outlineVariant: _Roomtone.darkHairline,
        inverseSurface: Color(0xFFE3EDEC),
        onInverseSurface: Color(0xFF0B1618),
        inversePrimary: Color(0xFF0B8578),
        surfaceTint: Color(0xFF3FBFAD),
        shadow: Color(0xFF000000),
        scrim: Color(0xFF000000),
      );

  /// The dark scheme with only its surface family re-grounded on black.
  ///
  /// Derived with `copyWith` on purpose: the petrol/teal accents, the status
  /// ambers and reds, and every `on*` pairing are shared with [dark], so the
  /// OLED variant can never drift away from the brand as those evolve.
  static ColorScheme _oledScheme() => _darkScheme().copyWith(
        surface: _Roomtone.oledSurface,
        surfaceContainerLowest: _Roomtone.oledGround,
        surfaceContainerLow: const Color(0xFF060C0D),
        surfaceContainer: _Roomtone.oledSurface,
        surfaceContainerHigh: const Color(0xFF0F1819),
        surfaceContainerHighest: _Roomtone.oledInset,
        outlineVariant: _Roomtone.oledHairline,
        // The inverse pair backs SnackBars and tooltips: light plate, and the
        // text on it has to be as black as the theme it belongs to.
        onInverseSurface: _Roomtone.oledGround,
      );

  static ColorScheme _lightScheme() => const ColorScheme(
        brightness: Brightness.light,
        primary: Color(0xFF0B8578),
        onPrimary: Color(0xFFFFFFFF),
        primaryContainer: Color(0xFFB9EFE7),
        onPrimaryContainer: Color(0xFF00201C),
        secondary: Color(0xFF256C93),
        onSecondary: Color(0xFFFFFFFF),
        secondaryContainer: Color(0xFFCBE6F7),
        onSecondaryContainer: Color(0xFF00243A),
        tertiary: Color(0xFF9C6220),
        onTertiary: Color(0xFFFFFFFF),
        tertiaryContainer: Color(0xFFFFDDB6),
        onTertiaryContainer: Color(0xFF2E1C05),
        error: Color(0xFFB4462F),
        onError: Color(0xFFFFFFFF),
        errorContainer: Color(0xFFFFDAD3),
        onErrorContainer: Color(0xFF410100),
        surface: _Roomtone.lightSurface,
        onSurface: _Roomtone.lightInk,
        surfaceContainerLowest: _Roomtone.lightGround,
        surfaceContainerLow: Color(0xFFF4F7F6),
        surfaceContainer: Color(0xFFEFF3F2),
        surfaceContainerHigh: Color(0xFFE7EDEC),
        surfaceContainerHighest: _Roomtone.lightInset,
        onSurfaceVariant: _Roomtone.lightMuted,
        outline: _Roomtone.lightOutline,
        outlineVariant: _Roomtone.lightHairline,
        inverseSurface: Color(0xFF16292B),
        onInverseSurface: Color(0xFFEBF0EF),
        inversePrimary: Color(0xFF3FBFAD),
        surfaceTint: Color(0xFF0B8578),
        shadow: Color(0xFF000000),
        scrim: Color(0xFF000000),
      );

  /// [oled] only ever applies to [Brightness.dark] — there is no low-luminance
  /// variant of a light theme, so it is ignored for light and the light build
  /// stays byte-identical.
  static ThemeData _build(Brightness brightness, {bool oled = false}) {
    final isDark = brightness == Brightness.dark;
    final isOled = isDark && oled;
    final colorScheme = isDark
        ? (isOled ? _oledScheme() : _darkScheme())
        : _lightScheme();
    final ground = isOled
        ? _Roomtone.oledGround
        : isDark
            ? _Roomtone.darkGround
            : _Roomtone.lightGround;
    final nav = isOled
        ? _Roomtone.oledNav
        : isDark
            ? _Roomtone.darkNav
            : _Roomtone.lightNav;
    final hairline = isOled
        ? _Roomtone.oledHairline
        : isDark
            ? _Roomtone.darkHairline
            : _Roomtone.lightHairline;

    return ThemeData(
      brightness: brightness,
      colorScheme: colorScheme,
      useMaterial3: true,
      scaffoldBackgroundColor: ground,
      canvasColor: ground,
      dividerColor: hairline,
      textTheme: AppTypography.textTheme(brightness),
      // Anything that bypasses the TextTheme still inherits the UI face
      // instead of falling back to the platform default.
      fontFamily: AppTypography.ui,
      extensions: <ThemeExtension<dynamic>>[
        StatusColors.forBrightness(brightness),
      ],
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
      dividerTheme: DividerThemeData(color: hairline, space: 1, thickness: 1),
      // Cards sit on `surface`, one step off the ground, so a card reads as a
      // raised object in dark and as white paper in light. Without this,
      // Card.filled would default to surfaceContainerHighest (the inset well).
      cardTheme: CardThemeData(
        color: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      // The bottom bar sits *below* the body in the Nightwatch stack: darker
      // than the ground in dark mode, paper-white in light.
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: nav,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorColor: colorScheme.primaryContainer,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: nav,
        indicatorColor: colorScheme.primaryContainer,
      ),
      // One place for every slider in the app: the camera card's volume and
      // pan, and the Settings buffer/sensitivity sliders. A ~17px thumb on a
      // 6px track is grabbable half-asleep; the M3 default is not.
      sliderTheme: SliderThemeData(
        trackHeight: 6,
        thumbShape: const RoundSliderThumbShape(
          enabledThumbRadius: 8.5,
          disabledThumbRadius: 6,
          pressedElevation: 4,
        ),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 22),
        activeTrackColor: colorScheme.primary,
        inactiveTrackColor: colorScheme.surfaceContainerHighest,
        thumbColor: colorScheme.primary,
        overlayColor: colorScheme.primary.withValues(alpha: 0.12),
      ),
    );
  }
}
