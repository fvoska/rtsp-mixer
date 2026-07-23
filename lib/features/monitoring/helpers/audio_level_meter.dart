import 'dart:math' as math;

/// Pure-Dart audio level metering from encoded bitrate.
///
/// The prebuilt media_kit FFmpeg has NO audio analysis filters (`ebur128`,
/// `astats`, `aformat` are all missing) and an unverified lavfi filter set via
/// `setProperty` kills the stream asynchronously (CLAUDE.md hard rule). The
/// loudness proxy is instead the mpv `audio-bitrate` property, which the poll
/// loop already reads: Unifi cameras stream VBR AAC, so encoded bitrate
/// correlates with signal energy — near-silence encodes to a very low bitrate,
/// a crying baby to a high one.
///
/// Everything in this file is pure math over plain Dart values (the only
/// import is `dart:math`), so it is unit-testable without native libs and can
/// never throw out of the poll loop's per-camera try/catch.

/// Bitrate mapped to level 0.0 — quieter than this reads as silence.
/// mpv's `audio-bitrate` is in bits/sec (the debug panel's `_formatBitrate`
/// treats it the same way).
const kBitrateFloorBps = 2000.0;

/// Bitrate mapped to level 1.0 — VBR AAC near its loud-signal ceiling.
const kBitrateCeilingBps = 96000.0;

/// Rolling history capacity: 20 samples at the 500 ms poll cadence = 10 s.
const kLevelHistoryCapacity = 20;

/// Variation window: the last 10 samples (~5 s) feed the activity statistic.
const kVariationWindow = 10;

/// Map an encoded audio bitrate (bits/sec) to an absolute pseudo-SPL level
/// in 0.0..1.0 using a fixed log scale between [kBitrateFloorBps] and
/// [kBitrateCeilingBps]:
///
///   level = (ln(bps) − ln(floor)) / (ln(ceiling) − ln(floor)), clamped 0..1
///
/// The mapping is deterministic — identical bounds on every camera, no
/// adaptive baseline — so the bar means the same thing on every card.
/// Null, non-positive, NaN, and infinite inputs return 0.0 (never NaN,
/// never throws): `audio-bitrate` strings originate from the camera's
/// stream via mpv and may be empty or garbage.
double bitrateToLevel(double? bps) {
  if (bps == null || !bps.isFinite || bps <= 0) return 0.0;
  final level = (math.log(bps) - math.log(kBitrateFloorBps)) /
      (math.log(kBitrateCeilingBps) - math.log(kBitrateFloorBps));
  if (level.isNaN) return 0.0;
  return level.clamp(0.0, 1.0);
}

/// Append [sample] to [history], keeping only the last [capacity] samples
/// (oldest dropped first, newest last).
///
/// Returns a NEW unmodifiable list — `List.unmodifiable` was chosen over a
/// fresh growable copy because the result is stored in an immutable state
/// object (`CameraAudioState.levelHistory`) and shared with the UI; making it
/// unmodifiable guarantees no consumer can mutate state out from under the
/// waveform painter's identity-based `shouldRepaint`. The input list is
/// never mutated. The hard cap also bounds memory over an 8 h session.
List<double> appendLevel(
  List<double> history,
  double sample, {
  int capacity = kLevelHistoryCapacity,
}) {
  final start = history.length >= capacity ? history.length - capacity + 1 : 0;
  return List.unmodifiable([...history.sublist(start), sample]);
}

/// Peak-to-trough variation (max − min, clamped 0..1) over the last [window]
/// samples of [history]. Returns 0.0 for fewer than 2 samples (never throws).
///
/// Peak-to-trough was chosen over standard deviation because: (a) with only
/// ~10 samples, std dev underestimates short cry bursts — a single loud spike
/// SHOULD light the border on a baby monitor; (b) levels are already 0..1 so
/// max − min is naturally normalized with no extra scaling constant; (c) it
/// is trivially explainable in the settings copy ("how much the level swung
/// recently"). No peak-hold decay is needed — the sliding window IS the
/// decay: a spike ages out after ~window samples.
double recentVariation(List<double> history, {int window = kVariationWindow}) {
  if (history.length < 2) return 0.0;
  final start = history.length > window ? history.length - window : 0;
  var min = double.infinity;
  var max = double.negativeInfinity;
  for (var i = start; i < history.length; i++) {
    final v = history[i];
    if (v < min) min = v;
    if (v > max) max = v;
  }
  if (min > max) return 0.0; // window somehow empty — defensive
  return (max - min).clamp(0.0, 1.0);
}
