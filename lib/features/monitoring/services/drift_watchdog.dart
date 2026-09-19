import '../../../core/logging/app_logger.dart';

/// Keeps each player at the live edge of its stream.
///
/// Background: the demuxer packet cache of a *live* RTSP stream can only
/// grow. mpv reads packets as fast as the network delivers them (with
/// `cache=yes` the `demuxer-readahead-secs` limit is ignored — `cache-secs`,
/// default ~1000 s, wins — so only `demuxer-max-bytes` bounds it), and
/// playback consumes them at exactly 1x. Every stall (Doze, an audio-focus
/// duck, a WiFi hiccup, the NVR's start-up burst) therefore leaves a residue
/// of delay that nothing drains. Over an 8+ hour night those residues add up
/// to seconds or minutes of lag.
///
/// Two tiers, in order:
///
/// 1. **Catch-up** — when the cache holds more than `target + engageMargin`
///    seconds, ask the caller to play slightly faster (`onSetSpeed`, mpv
///    `speed` with its built-in `scaletempo2` pitch correction) until the
///    cache is back at `target`, then return to 1.0. Silent, gapless, and it
///    is what mpv's own manual suggests for live sources. Transitions only:
///    the callback is never invoked on every tick.
/// 2. **Resync** — when the backlog exceeds `target + hardLimitSeconds` for
///    [confirmWindow] (catching up at 1.1x would take minutes, or the speed
///    path is not working on this build), fire `onFire` so the caller
///    performs a stop+open. Rate-limited by [cooldown].
///
/// Per CLAUDE.md ("no exception may kill a running audio stream"): every
/// callback is wrapped; the watchdog never throws.
class DriftWatchdog {
  DriftWatchdog({
    required this.onSetSpeed,
    required this.onFire,
    this.hardLimitSeconds = 10.0,
    this.confirmWindow = const Duration(seconds: 4),
    this.cooldown = const Duration(seconds: 30),
  });

  /// Called on catch-up transitions with the playback speed to apply:
  /// `catchUpSpeed` when engaging, `1.0` when the target is reached.
  final void Function(String cameraId, double speed) onSetSpeed;

  /// Called when a camera's backlog has exceeded the hard limit for
  /// [confirmWindow] and is not in cooldown. `detail` describes the observed
  /// cache depth and limit.
  final void Function(String cameraId, String detail) onFire;

  /// Seconds of backlog beyond the target past which catch-up is abandoned
  /// in favour of a full resync.
  final double hardLimitSeconds;

  /// How long the backlog must stay over the hard limit before a resync
  /// fires. Smooths over momentary spikes that resolve themselves.
  final Duration confirmWindow;

  /// Minimum time between resyncs for the same camera. Prevents resync
  /// storms when a camera is genuinely struggling to keep up.
  final Duration cooldown;

  // Per-camera over-hard-limit accumulators in milliseconds.
  final Map<String, int> _overMs = {};
  // Wall-clock of last resync per camera, for cooldown gating.
  final Map<String, DateTime> _lastFire = {};
  // Cameras currently playing at catch-up speed.
  final Set<String> _catchingUp = {};

  /// Whether [cameraId] is currently being played faster than realtime.
  bool isCatchingUp(String cameraId) => _catchingUp.contains(cameraId);

  /// Feed one observation of the demuxer's forward cache.
  ///
  /// [targetSeconds] is the backlog the mode wants to keep (near zero for
  /// realtime, the user's delay for buffered). Catch-up engages above
  /// `target + engageMarginSeconds` and disengages at or below `target`;
  /// the gap is the hysteresis that stops the speed from flapping.
  void recordCacheDuration({
    required String cameraId,
    required double cacheSeconds,
    required double targetSeconds,
    required int pollIntervalMs,
    double engageMarginSeconds = 0.5,
    double catchUpSpeed = 1.1,
  }) {
    if (!cacheSeconds.isFinite || cacheSeconds < 0) return;
    final over = cacheSeconds - targetSeconds;

    // Tier 1: gentle catch-up with hysteresis.
    if (!_catchingUp.contains(cameraId) && over > engageMarginSeconds) {
      _catchingUp.add(cameraId);
      appLog('DRIFT',
          '$cameraId: catch-up ${catchUpSpeed}x (cache=${cacheSeconds.toStringAsFixed(2)}s, '
          'target=${targetSeconds.toStringAsFixed(2)}s)');
      _setSpeed(cameraId, catchUpSpeed);
    } else if (_catchingUp.contains(cameraId) && over <= 0) {
      _catchingUp.remove(cameraId);
      appLog('DRIFT',
          '$cameraId: at live edge (cache=${cacheSeconds.toStringAsFixed(2)}s), speed 1.0x');
      _setSpeed(cameraId, 1.0);
    }

    // Tier 2: resync when the backlog is beyond what catch-up can fix.
    if (over <= hardLimitSeconds) {
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
        'cache=${cacheSeconds.toStringAsFixed(2)}s > ${(targetSeconds + hardLimitSeconds).toStringAsFixed(2)}s';
    appLog('DRIFT', '$cameraId: fire -> resync ($detail)');
    try {
      onFire(cameraId, detail);
    } catch (e) {
      appLog('DRIFT', '$cameraId: onFire callback threw: $e');
    }
  }

  void _setSpeed(String cameraId, double speed) {
    try {
      onSetSpeed(cameraId, speed);
    } catch (e) {
      appLog('DRIFT', '$cameraId: onSetSpeed($speed) threw: $e');
    }
  }

  /// Forget a camera's accumulators and catch-up state. Called after a
  /// (re)open — the freshly tuned player is back at speed 1.0 — so the next
  /// event can fire cleanly. Does not reset the cooldown: that is a
  /// wall-clock gate against rapid resync retries.
  void reset(String cameraId) {
    _overMs[cameraId] = 0;
    _catchingUp.remove(cameraId);
  }

  /// Clear all per-camera state. Call on stopMonitoring + onDispose.
  void resetAll() {
    _overMs.clear();
    _lastFire.clear();
    _catchingUp.clear();
  }
}
