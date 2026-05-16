import '../../../core/logging/app_logger.dart';

/// Watches each player's demuxer cache depth and fires a silent resync when
/// the live edge drifts further behind than the user-configured buffer.
///
/// Background: media_kit's prebuilt FFmpeg keeps RTSP packets in the demuxer
/// cache. With `demuxer-max-back-bytes=0` the already-played portion is
/// dropped, but the *forward* cache (`demuxer-cache-duration`) can still grow
/// past the playback buffer when the decoder briefly stalls. Over multi-hour
/// overnight sessions those small stalls compound into minutes of delay.
///
/// Strategy: poll `demuxer-cache-duration` each tick. When it exceeds the
/// allowed threshold (`bufferSeconds + tolerance`) consistently for the
/// confirm window, fire `onFire(cameraId, detail)`. The caller typically
/// performs a stop+open reconnect — that is the only reliable way to skip
/// buffered packets on this FFmpeg build (lavfi seek-to-live is not available
/// per the project's known-missing filters list).
///
/// Per CLAUDE.md ("no exception may kill a running audio stream"): all reads
/// are wrapped by the caller; the watchdog never throws.
class DriftWatchdog {
  DriftWatchdog({
    required this.onFire,
    this.confirmWindow = const Duration(seconds: 4),
    this.cooldown = const Duration(seconds: 30),
  });

  /// Called when a camera has been over-threshold for [confirmWindow] and is
  /// not in cooldown. `detail` describes the observed cache depth and limit.
  final void Function(String cameraId, String detail) onFire;

  /// How long the cache must remain over-threshold before firing. Smooths over
  /// momentary spikes that resolve themselves.
  final Duration confirmWindow;

  /// Minimum time between fires for the same camera. Prevents resync storms
  /// when a camera is genuinely struggling to keep up.
  final Duration cooldown;

  // Per-camera accumulators in milliseconds.
  final Map<String, int> _overMs = {};
  // Wall-clock of last fire per camera, for cooldown gating.
  final Map<String, DateTime> _lastFire = {};

  /// Feed one observation. Increments the over-threshold counter when the
  /// observed cache duration exceeds [thresholdSeconds]; resets it otherwise.
  ///
  /// When the counter exceeds [confirmWindow] and the camera is not in
  /// cooldown, calls [onFire] and resets the counter.
  void recordCacheDuration({
    required String cameraId,
    required double cacheSeconds,
    required double thresholdSeconds,
    required int pollIntervalMs,
  }) {
    if (cacheSeconds <= thresholdSeconds) {
      _overMs[cameraId] = 0;
      return;
    }

    final next = (_overMs[cameraId] ?? 0) + pollIntervalMs;
    _overMs[cameraId] = next;

    if (next < confirmWindow.inMilliseconds) return;

    final lastFire = _lastFire[cameraId];
    final now = DateTime.now();
    if (lastFire != null && now.difference(lastFire) < cooldown) {
      // In cooldown — keep accumulating but don't fire again yet.
      return;
    }

    _lastFire[cameraId] = now;
    _overMs[cameraId] = 0;

    final detail =
        'cache=${cacheSeconds.toStringAsFixed(2)}s > ${thresholdSeconds.toStringAsFixed(2)}s';
    appLog('DRIFT', '$cameraId: fire -> resync ($detail)');
    try {
      onFire(cameraId, detail);
    } catch (e) {
      appLog('DRIFT', '$cameraId: onFire callback threw: $e');
    }
  }

  /// Reset accumulators for a camera. Called after a successful reconnect so
  /// the next drift event can fire cleanly. Does not reset the cooldown — the
  /// cooldown is a wall-clock gate that protects against rapid retries.
  void reset(String cameraId) {
    _overMs[cameraId] = 0;
  }

  /// Clear all per-camera state. Call on stopMonitoring + onDispose.
  void resetAll() {
    _overMs.clear();
    _lastFire.clear();
  }
}
