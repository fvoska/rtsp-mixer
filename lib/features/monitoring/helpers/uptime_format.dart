/// Shared, pure uptime formatting.
///
/// Lifted out of `HealthSummaryScreen` so the Monitor header status line, the
/// active-session mini-bar, and the health summary all render the same shape
/// rather than three near-copies drifting apart.
library;

/// `42s` / `7m` / `6h 12m`.
///
/// Total function: a negative duration (clock skew, or a `startedAt` that
/// somehow lands in the future) collapses to `0s` rather than rendering
/// `-1h -3m`. Callers render this inside a live 1-second ticker, so it must
/// never throw.
String formatUptime(Duration d) {
  if (d.isNegative) return '0s';
  if (d.inMinutes < 1) return '${d.inSeconds}s';
  if (d.inHours < 1) return '${d.inMinutes}m';
  final h = d.inHours;
  final m = d.inMinutes - h * 60;
  return '${h}h ${m}m';
}
