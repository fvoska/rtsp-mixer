import '../../../core/logging/app_logger.dart';

/// RELY-03: detects TCP-open-but-no-audio zombie streams via 4 signals (D-06).
///
/// Ages each signal in milliseconds. When quorum score >= 2, fires the
/// `onFire` callback (typically → ReconnectSupervisor.requestReconnect).
/// Hardcoded 60s threshold per signal (D-05, D-08) — not user-configurable.
///
/// Weighting (RESEARCH §Section 5 recommendation):
/// - PTS stall: weight 2 (most specific signal — advances even during silence)
/// - buffering stuck: weight 1
/// - bitrate=0: weight 1 (legitimately 0 at stream start; weak alone)
/// - no audioParams: weight 1 (sparse in steady state; weak alone)
/// Fires at score >= 2, i.e., PTS alone OR any two of the others.
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
  /// PTS stall weight 2; others weight 1 each. Fire threshold is >= 2.
  int zombieScore(String cameraId) {
    var score = 0;
    if ((_ptsStallMs[cameraId] ?? 0) >= thresholdMs) score += 2;
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
