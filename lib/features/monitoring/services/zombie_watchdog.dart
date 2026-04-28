import '../../../core/logging/app_logger.dart';

/// RELY-03: detects TCP-open-but-no-audio zombie streams via 4 signals (D-06).
///
/// Ages each signal in milliseconds. When quorum score >= 2 *and* PTS-stall
/// is among the signals, fires the `onFire` callback (typically →
/// ReconnectSupervisor.requestReconnect). Hardcoded 60s threshold per signal
/// (D-05, D-08) — not user-configurable.
///
/// Why PTS-stall is necessary (CR-01 fix):
/// Of the four signals, only PTS-stall is *naturally* reset every poll
/// during health (`recordPtsAdvance` fires from `_pollAudioLevels` whenever
/// audio data flows). The other three are edge-triggered:
///   - `buffering=false` only fires on `true→false` transitions
///   - `audioParams` only fires when params change
///   - `bitrate=0` is reset every poll, but is legitimately 0 during startup
/// In steady state, both `_bufferingStuckMs` and `_noAudioParamsMs` will
/// drift to threshold without ever indicating a real problem. Without
/// gating on PTS-stall, the watchdog would false-positive every ~60s on a
/// healthy stream. So: PTS-stall is the necessary signal; the other three
/// only *corroborate* it.
///
/// Weighting:
/// - PTS-stall: weight 2 (necessary condition — must be present to fire)
/// - buffering stuck: weight 1 (corroborating)
/// - bitrate=0: weight 1 (corroborating)
/// - no audioParams: weight 1 (corroborating)
/// Fires at score >= 2, requiring PTS-stall (which alone gives score 2).
class ZombieWatchdog {
  ZombieWatchdog({
    required this.onFire,
    this.threshold = const Duration(seconds: 60),
  });

  /// Called when quorum score >= 2 for a camera. Detail summarises which
  /// signals crossed (e.g., "PTS stall + buffering stuck").
  final void Function(String cameraId, String detail) onFire;
  final Duration threshold;

  // Signal age in milliseconds per camera (D-06).
  final Map<String, int> _ptsStallMs = {};
  final Map<String, int> _bufferingStuckMs = {};
  final Map<String, int> _bitrateZeroMs = {};
  final Map<String, int> _noAudioParamsMs = {};

  // Latches prevent repeated fires on every tick while a zombie condition persists.
  // Cleared when the score drops back below 2 (typically after reconnect resets signals).
  final Map<String, bool> _fired = {};

  int get thresholdMs => threshold.inMilliseconds;

  /// Tick every poll interval (500ms by default). Increments all four counters
  /// by `pollIntervalMs`. Caller feeds positive-signal resets separately via
  /// the `record*` methods BEFORE calling tick for that camera on the same pass.
  void tick(String cameraId, int pollIntervalMs) {
    _ptsStallMs[cameraId] = (_ptsStallMs[cameraId] ?? 0) + pollIntervalMs;
    _bufferingStuckMs[cameraId] =
        (_bufferingStuckMs[cameraId] ?? 0) + pollIntervalMs;
    _bitrateZeroMs[cameraId] = (_bitrateZeroMs[cameraId] ?? 0) + pollIntervalMs;
    _noAudioParamsMs[cameraId] =
        (_noAudioParamsMs[cameraId] ?? 0) + pollIntervalMs;

    final score = zombieScore(cameraId);
    if (score >= 2 && !(_fired[cameraId] ?? false)) {
      _fired[cameraId] = true;
      final detail = _describeFire(cameraId);
      appLog('ZOMBIE', '$cameraId: detected (score=$score, $detail)');
      try {
        onFire(cameraId, detail);
      } catch (e) {
        appLog('ZOMBIE', '$cameraId: onFire callback threw: $e');
      }
    } else if (score < 2 && (_fired[cameraId] ?? false)) {
      // Score dropped — reset the latch so the next zombie can fire again.
      _fired[cameraId] = false;
    }
  }

  /// Positive signal 1: audio-pts advanced during this poll.
  void recordPtsAdvance(String cameraId) => _ptsStallMs[cameraId] = 0;

  /// Positive signal 2: buffering is currently false.
  void recordBufferingFalse(String cameraId) => _bufferingStuckMs[cameraId] = 0;

  /// Negative signal 2: buffering is currently true — age continues.
  /// (No-op by design; tick() handles the accumulation.)
  void recordBufferingTrue(String cameraId) {}

  /// Positive signal 3: audio-bitrate > 0.
  void recordBitrateNonZero(String cameraId) => _bitrateZeroMs[cameraId] = 0;

  /// Positive signal 4: audioParams event fired.
  void recordAudioParams(String cameraId) => _noAudioParamsMs[cameraId] = 0;

  /// Compute weighted quorum score for a camera.
  /// PTS-stall is a necessary condition: without it, score is 0 regardless
  /// of the other signals (CR-01 fix — prevents steady-state false positives
  /// from edge-triggered signals never recurring during health).
  /// PTS-stall weight 2; corroborating signals weight 1 each.
  /// Fire threshold is >= 2.
  int zombieScore(String cameraId) {
    if ((_ptsStallMs[cameraId] ?? 0) < thresholdMs) return 0;
    var score = 2; // PTS-stall present.
    if ((_bufferingStuckMs[cameraId] ?? 0) >= thresholdMs) score += 1;
    if ((_bitrateZeroMs[cameraId] ?? 0) >= thresholdMs) score += 1;
    if ((_noAudioParamsMs[cameraId] ?? 0) >= thresholdMs) score += 1;
    return score;
  }

  /// Reset all counters for a camera (call after a successful reconnect).
  void reset(String cameraId) {
    _ptsStallMs[cameraId] = 0;
    _bufferingStuckMs[cameraId] = 0;
    _bitrateZeroMs[cameraId] = 0;
    _noAudioParamsMs[cameraId] = 0;
    _fired[cameraId] = false;
  }

  /// Clear all per-camera state. Call on stopMonitoring + onDispose.
  void resetAll() {
    _ptsStallMs.clear();
    _bufferingStuckMs.clear();
    _bitrateZeroMs.clear();
    _noAudioParamsMs.clear();
    _fired.clear();
  }

  String _describeFire(String cameraId) {
    final parts = <String>[];
    if ((_ptsStallMs[cameraId] ?? 0) >= thresholdMs) parts.add('PTS stall');
    if ((_bufferingStuckMs[cameraId] ?? 0) >= thresholdMs) {
      parts.add('buffering stuck');
    }
    if ((_bitrateZeroMs[cameraId] ?? 0) >= thresholdMs) parts.add('bitrate=0');
    if ((_noAudioParamsMs[cameraId] ?? 0) >= thresholdMs) {
      parts.add('no audioParams');
    }
    return parts.join(' + ');
  }
}
