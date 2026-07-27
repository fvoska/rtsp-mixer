/// Pure-Dart dynamics for REAL audio levels (dBFS) from the native sidecar.
///
/// Companion to `audio_level_meter.dart` (the bitrate proxy, kept as the
/// fallback for platforms without the sidecar). Everything here is plain math
/// over injected values and timestamps — no platform imports, deterministic,
/// unit-testable, and incapable of throwing out of the poll loop.
library;

/// dBFS mapped to meter level 0.0. Unifi camera mics with AGC idle around
/// -55..-40 dBFS; -60 reads as silence on every camera model tried.
const kMeterFloorDb = -60.0;

/// dBFS mapped to meter level 1.0. Loud crying close to the camera peaks
/// around -10..-3 dBFS; -5 keeps the top of the bar reachable.
const kMeterCeilingDb = -5.0;

/// Native levels older than this are considered stale and the poll falls
/// back to the bitrate proxy (sidecar reconnecting or dead).
const kNativeLevelFreshness = Duration(seconds: 3);

/// Map an RMS level in dBFS onto the meter's 0.0..1.0 scale, linear in dB
/// between [kMeterFloorDb] and [kMeterCeilingDb]. Deterministic — identical
/// bounds on every camera, so the bar means the same thing on every card.
/// Non-finite input returns 0.0 (never NaN, never throws).
double dbfsToLevel(double dbfs) {
  if (!dbfs.isFinite) return 0.0;
  final level = (dbfs - kMeterFloorDb) / (kMeterCeilingDb - kMeterFloorDb);
  return level.clamp(0.0, 1.0);
}

/// Seconds of history the noise-floor percentile looks back over.
const kFloorWindowSeconds = 300;

/// Percentile of the window used as the noise floor. 10th: even during a
/// long cry, brief between-sob quiets keep the floor honest.
const kFloorPercentile = 0.10;

/// dB of excess over the noise floor that maps to activity 1.0. With the
/// activity slider's existing thresholds (high 0.05 / medium 0.15 / low 0.3)
/// this puts "medium" at ~4.5 dB over floor and "low" at ~9 dB — speech and
/// crying land well above, hiss well below.
const kActivityFullScaleDb = 30.0;

/// Attack time constant: how fast the smoothed level rises toward a burst.
/// Short so a single cry lights the border within a couple of samples.
const kAttackTauMs = 250.0;

/// Release time constant: how slowly activity decays after sound stops, so
/// the border doesn't strobe between sobs.
const kReleaseTauMs = 2500.0;

/// Converts a stream of (dBFS, timestamp) samples into a 0..1 activity
/// statistic: attack/release-smoothed level, measured as dB of excess over
/// an adaptive noise floor (rolling low percentile), scaled by
/// [kActivityFullScaleDb].
///
/// Unlike the bitrate era's peak-to-trough variation, this reflects how loud
/// the room is *relative to its own quiet baseline* — a fan turning on stops
/// triggering after a few minutes as the floor absorbs it, while crying and
/// talking stand tall above it. One instance per camera; state resets are
/// unnecessary across stream reconnects because the sidecar feed is
/// independent of playback.
class ActivityDetector {
  double? _smoothedDb;
  int? _lastFeedMs;

  // Noise floor: per-second minima in a ring buffer covering
  // [kFloorWindowSeconds]; floor = [kFloorPercentile] of the buffer.
  final List<double> _secondMinima = [];
  double _currentSecondMin = double.infinity;
  int? _currentSecondStartMs;
  double? _cachedFloorDb;

  /// Feed one native RMS sample. Non-finite samples and non-monotonic
  /// timestamps are ignored (never throws).
  void feed(double dbfs, int nowMs) {
    if (!dbfs.isFinite) return;
    final last = _lastFeedMs;
    if (last != null && nowMs < last) return;

    // Attack/release smoothing (time-based EMA so cadence changes don't
    // change the response).
    final prev = _smoothedDb;
    if (prev == null || last == null) {
      _smoothedDb = dbfs;
    } else {
      final dtMs = (nowMs - last).toDouble();
      final tau = dbfs > prev ? kAttackTauMs : kReleaseTauMs;
      // 1 - e^(-dt/tau) without importing dart:math: for the dt/tau ranges
      // here (dt ~100ms), the 2nd-order Padé form is within 1% of exact.
      final x = dtMs / tau;
      final alpha = (x >= 1.0) ? 1.0 : x / (1.0 + x / 2.0 + x * x / 12.0);
      _smoothedDb = prev + (dbfs - prev) * alpha;
    }
    _lastFeedMs = nowMs;

    // Per-second minimum into the floor window.
    _currentSecondStartMs ??= nowMs;
    if (dbfs < _currentSecondMin) _currentSecondMin = dbfs;
    if (nowMs - _currentSecondStartMs! >= 1000) {
      if (_currentSecondMin.isFinite) {
        _secondMinima.add(_currentSecondMin);
        if (_secondMinima.length > kFloorWindowSeconds) {
          _secondMinima.removeAt(0);
        }
        _cachedFloorDb = null; // recompute lazily
      }
      _currentSecondStartMs = nowMs;
      _currentSecondMin = double.infinity;
    }
  }

  /// Adaptive noise floor in dBFS, or null before any full second of
  /// samples has been collected. Clamped to [-90, -20] so a camera that is
  /// constantly loud can't push the floor high enough to mask real events.
  double? get floorDb {
    if (_secondMinima.isEmpty) return null;
    var floor = _cachedFloorDb;
    if (floor == null) {
      final sorted = List<double>.from(_secondMinima)..sort();
      final idx = (sorted.length * kFloorPercentile).floor();
      floor = sorted[idx.clamp(0, sorted.length - 1)];
      _cachedFloorDb = floor;
    }
    return floor.clamp(-90.0, -20.0);
  }

  /// Smoothed level in dBFS (null before the first sample). Exposed for the
  /// debug panel.
  double? get smoothedDb => _smoothedDb;

  /// Current activity 0..1: smoothed excess over the noise floor scaled by
  /// [kActivityFullScaleDb]. Returns 0.0 while warming up (< 5 s of floor
  /// history) so the border can't light from an unlearned baseline.
  double get activity {
    final smoothed = _smoothedDb;
    final floor = floorDb;
    if (smoothed == null || floor == null || _secondMinima.length < 5) {
      return 0.0;
    }
    return ((smoothed - floor) / kActivityFullScaleDb).clamp(0.0, 1.0);
  }
}
