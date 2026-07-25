import 'package:flutter/material.dart';

import '../logging/app_logger.dart';

/// Per-brightness stream-status palette, carried on [ThemeData.extensions].
///
/// These used to be three fixed `const Color`s on `AppTheme`, which meant the
/// same mid-green/mid-red rendered on both a near-black card and a white one —
/// unreadable in light mode. Routing them through a [ThemeExtension] lets each
/// brightness pick a colour that actually clears a contrast threshold against
/// its own surface.
@immutable
class StatusColors extends ThemeExtension<StatusColors> {
  /// Stream is playing and healthy.
  final Color live;

  /// First connection attempt in flight.
  final Color connecting;

  /// A previously-live stream dropped and is being re-established.
  final Color reconnecting;

  /// Stream failed, or the camera is unreachable.
  final Color offline;

  /// Degraded-but-not-broken (zombie suspicion, WiFi wobble, alerts).
  final Color warning;

  const StatusColors({
    required this.live,
    required this.connecting,
    required this.reconnecting,
    required this.offline,
    required this.warning,
  });

  /// Roomtone dark: saturated enough to read at 3am on the petrol ground
  /// without being a light source of its own.
  static const dark = StatusColors(
    live: Color(0xFF3FBFAD),
    connecting: Color(0xFF5FA8D3),
    reconnecting: Color(0xFFE0A458),
    offline: Color(0xFFE0715B),
    warning: Color(0xFFE0A458),
  );

  /// Roomtone light: darkened so each colour clears ~3:1 against a white card.
  /// The old fixed dark-mode green measured well under 2:1 here.
  static const light = StatusColors(
    live: Color(0xFF0B8578),
    connecting: Color(0xFF256C93),
    reconnecting: Color(0xFF9C6220),
    offline: Color(0xFFB4462F),
    warning: Color(0xFF9C6220),
  );

  /// The instance matching [brightness]. Never null, never throws.
  static StatusColors forBrightness(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  /// Single-lookup accessor for call sites.
  ///
  /// Defensive by design (CLAUDE.md): a widget built under an ad-hoc
  /// [ThemeData] that never registered this extension must still render. We
  /// fall back to the brightness-matched instance and log once, rather than
  /// returning null or throwing out of a `build` that may be painting a live
  /// camera card overnight.
  static StatusColors of(BuildContext context) {
    ThemeData theme;
    try {
      theme = Theme.of(context);
    } catch (e) {
      _warnOnce('no Theme in scope ($e)');
      return light;
    }
    final ext = theme.extension<StatusColors>();
    if (ext != null) return ext;
    _warnOnce('theme has no StatusColors extension registered');
    return forBrightness(theme.brightness);
  }

  static bool _warned = false;

  static void _warnOnce(String reason) {
    if (_warned) return;
    _warned = true;
    try {
      appLog('THEME', 'StatusColors fallback in use: $reason');
    } catch (_) {
      // Logging is never worth a crash.
    }
  }

  /// Test seam: lets a test assert the fallback logs without being order-
  /// dependent on other tests having already tripped the one-shot guard.
  @visibleForTesting
  static void resetFallbackWarningForTest() => _warned = false;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StatusColors &&
          live == other.live &&
          connecting == other.connecting &&
          reconnecting == other.reconnecting &&
          offline == other.offline &&
          warning == other.warning;

  @override
  int get hashCode =>
      Object.hash(live, connecting, reconnecting, offline, warning);

  @override
  StatusColors copyWith({
    Color? live,
    Color? connecting,
    Color? reconnecting,
    Color? offline,
    Color? warning,
  }) =>
      StatusColors(
        live: live ?? this.live,
        connecting: connecting ?? this.connecting,
        reconnecting: reconnecting ?? this.reconnecting,
        offline: offline ?? this.offline,
        warning: warning ?? this.warning,
      );

  @override
  StatusColors lerp(ThemeExtension<StatusColors>? other, double t) {
    if (other is! StatusColors) return this;
    return StatusColors(
      live: Color.lerp(live, other.live, t) ?? live,
      connecting: Color.lerp(connecting, other.connecting, t) ?? connecting,
      reconnecting:
          Color.lerp(reconnecting, other.reconnecting, t) ?? reconnecting,
      offline: Color.lerp(offline, other.offline, t) ?? offline,
      warning: Color.lerp(warning, other.warning, t) ?? warning,
    );
  }
}

/// `context.statusColors` — keeps every call site a single expression.
extension StatusColorsX on BuildContext {
  StatusColors get statusColors => StatusColors.of(this);
}

/// `theme.statusColors` — same fallback contract, for the handful of helpers
/// that are already handed a [ThemeData] instead of a [BuildContext].
extension StatusColorsThemeX on ThemeData {
  StatusColors get statusColors {
    final ext = extension<StatusColors>();
    if (ext != null) return ext;
    StatusColors._warnOnce('ThemeData has no StatusColors extension');
    return StatusColors.forBrightness(brightness);
  }
}
