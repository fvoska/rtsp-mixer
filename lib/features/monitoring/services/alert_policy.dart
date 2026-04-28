import 'dart:async';

import '../../../core/logging/app_logger.dart';

/// D-04 one-shot alert policy. Owns per-camera Timer + fired flag.
/// Extracted from AudioPlayerNotifier for unit-testability.
///
/// Behavior contract:
/// - `armIfAbsent` is idempotent: re-arming during an active timer does NOT
///   reset the clock (continuous-outage threshold per D-04).
/// - The timer fires `onFire(cameraId)` exactly once per outage cycle.
/// - `clear` cancels any pending timer AND resets the fired flag so the next
///   outage can fire again.
/// - `cancelAll` is the teardown path — no further fires after it returns.
class AlertPolicy {
  AlertPolicy({
    required this.onFire,
    this.threshold = const Duration(minutes: 5),
  });

  /// Invoked exactly once per outage cycle, after `threshold` of continuous
  /// non-playing.
  final void Function(String cameraId) onFire;
  final Duration threshold;

  final Map<String, Timer> _timers = {};
  final Map<String, bool> _fired = {};

  /// Called when a camera enters a non-playing state. Idempotent —
  /// does not reset the clock if a timer is already pending.
  void armIfAbsent(String cameraId) {
    if (_timers.containsKey(cameraId)) return;
    _timers[cameraId] = Timer(threshold, () {
      try {
        if (_fired[cameraId] == true) return;
        _fired[cameraId] = true;
        onFire(cameraId);
      } catch (e) {
        appLog('NOTIF', 'AlertPolicy onFire crashed: $e');
      } finally {
        _timers.remove(cameraId);
      }
    });
  }

  /// Called when a camera returns to playing. Cancels pending Timer,
  /// resets the fired flag so a subsequent outage can fire again.
  void clear(String cameraId) {
    _timers.remove(cameraId)?.cancel();
    _fired[cameraId] = false;
  }

  /// Teardown — cancels all pending Timers. Call on stopMonitoring + onDispose.
  void cancelAll() {
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
    _fired.clear();
  }

  /// Test hook.
  bool isArmed(String cameraId) => _timers.containsKey(cameraId);
  bool hasFired(String cameraId) => _fired[cameraId] ?? false;
}
