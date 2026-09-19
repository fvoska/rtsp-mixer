import 'dart:collection';
import 'dart:math' as math;

/// Pure-Dart audio level tracking: any dB-domain loudness signal in, one
/// smoothed, room-relative 0..1 level out.
///
/// Two signals feed it:
///
/// * **PCM tap (preferred).** A second, silent mpv player per camera writes
///   decoded 8 kHz mono PCM into a named pipe and `PcmLevelMeter` turns each
///   tick's bytes into a real dBFS reading. See `pcm_level_tap.dart`.
/// * **Encoded bitrate (fallback).** On platforms without FIFOs, or while the
///   tap is still connecting, the mpv `audio-bitrate` property stands in.
///   Unifi cameras stream near-constant-bitrate AAC, so it barely moves —
///   it is a last resort, not a meter.
///
/// Neither comes with a useful absolute scale — camera microphone gain
/// differs per device and per Protect "mic volume" setting, and the bitrate
/// has no scale at all — so [AudioLevelTracker] measures loudness RELATIVE
/// to the room: it tracks the quietest the stream has been over the last few
/// minutes (the noise floor) and reports how far above that floor the signal
/// is right now, on a scale that self-calibrates to the range the stream
/// actually spans. The output is one number in 0..1 that both the card
/// border and the waveform history consume, so what the border shows IS
/// what the chart shows.
///
/// Everything in this file is pure math over plain Dart values (only
/// `dart:math` and `dart:collection` are imported), so it is unit-testable
/// without native libs and can never throw out of the poll loop's per-camera
/// try/catch.

/// Poll cadence of the level meter. 4 samples/s is fast enough that a
/// 300 ms border tween between samples reads as continuous, and cheap enough
/// (two synchronous mpv property reads per camera) to run all night.
const kLevelPollInterval = Duration(milliseconds: 250);

/// Rolling history span shown by the waveform chart.
const kLevelHistorySeconds = 60;

/// Rolling history capacity: 60 s at the 250 ms poll cadence.
const kLevelHistoryCapacity = 240;

/// Noise-floor calibration window. The floor is the quietest one-second
/// minimum seen within this window, so a cry that lasts longer than this
/// will eventually be absorbed into the floor — an acceptable trade against
/// a floor that never recovers after a stream started during a loud moment.
const kCalibrationWindowSeconds = 300.0;

/// Calibration samples are pushed once per second (the minimum of the
/// smoothed level within that second), so a 1 s dip lowers the floor but a
/// single jittery packet cannot.
const kCalibrationStrideSeconds = 1.0;

/// mpv's first bitrate readings after `open` are unreliable (it reports the
/// first packet or two before it has a real timestamp distance). Nothing in
/// the first two seconds of flow feeds the calibration ring.
const kWarmupSeconds = 2.0;

/// Smallest range the meter will spread over 0..1 for the PCM tap. A quiet
/// nursery's microphone self-noise wanders by a few dB; 30 dB keeps that
/// near zero instead of auto-gaining it to a full-scale display of nothing,
/// and leaves speech (~25 dB above a quiet room) short of full scale so a
/// cry (35-45 dB) still reads as louder before the ceiling has learned it.
const kPcmMinSpanDb = 30.0;

/// Largest range the meter will spread over 0..1 for the PCM tap. Beyond
/// this a louder sound just pins the meter — nobody needs to distinguish
/// "very loud" from "extremely loud" on a baby monitor.
const kPcmMaxSpanDb = 50.0;

/// Span clamps for the bitrate fallback, whose whole dynamic range is a
/// handful of dB.
const kBitrateMinSpanDb = 6.0;
const kBitrateMaxSpanDb = 24.0;

/// Kept for callers that predate the PCM tap.
const kMinSpanDb = kBitrateMinSpanDb;
const kMaxSpanDb = kBitrateMaxSpanDb;

/// Time constant of the short EMA applied to the dB signal before anything
/// else looks at it. Per-packet bitrate is jittery; a 0.4 s smoothing tames
/// it without making a cry onset lag noticeably.
const kAttackSeconds = 0.4;

/// Time constant of the slower EMA that feeds noise-floor calibration. A
/// single tiny packet moves the fast display signal by several dB, and
/// baking that into the floor would pin the meter high for the whole
/// calibration window; through a 2 s smoothing one outlier shifts the floor
/// by well under 3 dB, while a genuinely quiet room still registers within
/// a few seconds.
const kCalibrationSmoothingSeconds = 2.0;

/// Time constant of the display envelope's release. The level rises
/// immediately with the smoothed signal and decays with this time constant,
/// like a VU meter, so the border fades out rather than blinking off.
const kReleaseSeconds = 0.8;

/// Encoded bitrate (bits/sec) to decibels: `10·log10(bps)`.
///
/// Returns null for anything that is not a positive finite number — the
/// `audio-bitrate` string originates from the camera's stream via mpv and may
/// be empty or garbage. Never throws, never returns NaN.
double? bitrateToDb(double? bps) {
  if (bps == null || !bps.isFinite || bps <= 0) return null;
  final db = 10.0 * math.log(bps) / math.ln10;
  return db.isFinite ? db : null;
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

/// Per-camera loudness tracker: turns a stream of dB readings into a
/// smoothed, noise-floor-relative level in 0..1.
///
/// One instance per live stream, fed once per poll tick via [update]. Create
/// a fresh instance whenever a stream is (re)opened, or the level source
/// changes, so a previous calibration cannot misrepresent the new signal.
class AudioLevelTracker {
  /// Preset for real dBFS readings from the PCM tap.
  factory AudioLevelTracker.pcm() => AudioLevelTracker(
        minSpanDb: kPcmMinSpanDb,
        maxSpanDb: kPcmMaxSpanDb,
      );

  /// Preset for the encoded-bitrate fallback.
  factory AudioLevelTracker.bitrate() => AudioLevelTracker(
        minSpanDb: kBitrateMinSpanDb,
        maxSpanDb: kBitrateMaxSpanDb,
      );

  AudioLevelTracker({
    this.calibrationWindowSeconds = kCalibrationWindowSeconds,
    this.calibrationStrideSeconds = kCalibrationStrideSeconds,
    this.warmupSeconds = kWarmupSeconds,
    this.minSpanDb = kMinSpanDb,
    this.maxSpanDb = kMaxSpanDb,
    this.attackSeconds = kAttackSeconds,
    this.calibrationSmoothingSeconds = kCalibrationSmoothingSeconds,
    this.releaseSeconds = kReleaseSeconds,
  });

  final double calibrationWindowSeconds;
  final double calibrationStrideSeconds;
  final double warmupSeconds;
  final double minSpanDb;
  final double maxSpanDb;
  final double attackSeconds;
  final double calibrationSmoothingSeconds;
  final double releaseSeconds;

  /// Seconds of *flowing* audio seen so far (drives warm-up and the
  /// calibration stride).
  double _flowSeconds = 0.0;

  /// Short-EMA-smoothed dB signal, null until the first valid reading.
  double? _smoothedDb;

  /// Slow-EMA-smoothed dB signal that feeds calibration only.
  double? _calibrationDb;

  /// Extremes of the calibration-smoothed dB within the current stride.
  double _strideMin = double.infinity;
  double _strideMax = double.negativeInfinity;
  double _strideElapsed = 0.0;

  /// One entry per completed stride: flow-time at push plus that stride's
  /// minimum (feeds the floor) and maximum (feeds the ceiling).
  final Queue<_CalibrationSample> _ring = Queue<_CalibrationSample>();

  double _level = 0.0;

  /// The current display level, 0..1. What the border and the waveform show.
  double get level => _level;

  /// Current smoothed signal in dB, or null before the first valid reading.
  double? get smoothedDb => _smoothedDb;

  /// The room's quiet level in dB, or null until calibration has a sample.
  double? get floorDb =>
      _ring.isEmpty ? null : _ring.map((s) => s.min).reduce(math.min);

  /// The loudest calibration sample in dB, or null until calibration has one.
  double? get ceilingDb =>
      _ring.isEmpty ? null : _ring.map((s) => s.max).reduce(math.max);

  /// dB range currently mapped onto 0..1 (clamped to [minSpanDb, maxSpanDb]).
  double get spanDb {
    final floor = floorDb;
    final ceiling = ceilingDb;
    if (floor == null || ceiling == null) return minSpanDb;
    return (ceiling - floor).clamp(minSpanDb, maxSpanDb);
  }

  /// Feed one poll tick and return the new display level.
  ///
  /// [db] is this tick's loudness reading in any consistent dB scale —
  /// dBFS from the PCM tap, or `bitrateToDb` of the bitrate fallback. Null
  /// means no reading this tick (the tap delivered no bytes, mpv has not
  /// published a bitrate yet): the level holds. [flowing] is the poll
  /// loop's PTS-advance verdict: false means no audio is arriving, so the
  /// level decays to zero regardless of any stale reading. [dtSeconds] is
  /// the time since the previous call.
  ///
  /// Never throws and never returns NaN: every arithmetic step is guarded
  /// so a garbage reading degrades to "hold the previous level".
  double update({
    required double? db,
    required bool flowing,
    required double dtSeconds,
  }) {
    final dt = (dtSeconds.isFinite && dtSeconds > 0) ? dtSeconds : 0.0;

    double target;
    if (!flowing) {
      // No audio arriving: the meter falls to zero. The floor is left alone —
      // a stalled stream says nothing about how quiet the room is.
      target = 0.0;
    } else {
      if (db == null || !db.isFinite) {
        // Flowing but no reading this tick — hold the current level so a
        // live stream never flashes as silent for a moment.
        target = _level;
      } else {
        _flowSeconds += dt;
        _smoothedDb = _ema(_smoothedDb, db, dt, attackSeconds);
        _calibrationDb =
            _ema(_calibrationDb, db, dt, calibrationSmoothingSeconds);
        _calibrate(_calibrationDb!, dt);
        target = _normalise(_smoothedDb!);
      }
    }

    _level = _release(_level, target, dt);
    if (!_level.isFinite) _level = 0.0;
    return _level;
  }

  double _ema(double? previous, double sample, double dt, double tau) {
    if (previous == null) return sample;
    if (tau <= 0) return sample;
    final alpha = 1.0 - math.exp(-dt / tau);
    final next = previous + (sample - previous) * alpha;
    return next.isFinite ? next : previous;
  }

  /// Push each one-second stride's extremes into the calibration ring and
  /// evict entries older than the window. Nothing is recorded during
  /// warm-up.
  void _calibrate(double calibrationDb, double dt) {
    if (_flowSeconds < warmupSeconds) return;
    _strideMin = math.min(_strideMin, calibrationDb);
    _strideMax = math.max(_strideMax, calibrationDb);
    _strideElapsed += dt;
    if (_strideElapsed < calibrationStrideSeconds && _ring.isNotEmpty) return;
    // First sample after warm-up is pushed immediately so the floor exists
    // as soon as possible; later ones once per stride.
    _ring.addLast(_CalibrationSample(_flowSeconds, _strideMin, _strideMax));
    _strideMin = double.infinity;
    _strideMax = double.negativeInfinity;
    _strideElapsed = 0.0;
    while (_ring.isNotEmpty &&
        _flowSeconds - _ring.first.at > calibrationWindowSeconds) {
      _ring.removeFirst();
    }
  }

  double _normalise(double smoothedDb) {
    final floor = floorDb;
    if (floor == null) return 0.0; // still warming up: nothing to compare to
    final raw = (smoothedDb - floor) / spanDb;
    if (!raw.isFinite) return 0.0;
    return raw.clamp(0.0, 1.0);
  }

  /// VU-style envelope: instant attack, exponential release.
  double _release(double current, double target, double dt) {
    if (target >= current) return target;
    if (releaseSeconds <= 0) return target;
    final alpha = 1.0 - math.exp(-dt / releaseSeconds);
    return current + (target - current) * alpha;
  }
}

class _CalibrationSample {
  const _CalibrationSample(this.at, this.min, this.max);
  final double at;
  final double min;
  final double max;
}
