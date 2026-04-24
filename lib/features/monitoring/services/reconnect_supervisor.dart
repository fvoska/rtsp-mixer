import 'dart:async';
import 'dart:math';

import '../../../core/logging/app_logger.dart';

/// Per-camera operational state held by the supervisor.
/// NOT part of UI state — `CameraAudioState` stays minimal.
class _ReconnectState {
  int attempt = 0;                   // current backoff attempt (0 = first attempt)
  Timer? retryTimer;                 // scheduled next retry
  Timer? alertTimer;                 // 5-min alert countdown (set by Plan 04)
  bool alertFired = false;           // one-shot gate (D-04; enforced by Plan 04)
  bool inFlight = false;             // dedupe guard (Pattern 3)
  DateTime? firstDropAt;             // for health summary downtime
}

/// D-01 exponential backoff with ±20% jitter, capped at 30s.
/// Attempts 0..5 yield 1,2,4,8,16,30 (pre-jitter); attempt>=5 stays at 30.
Duration computeBackoff(int attempt, {Random? random}) {
  final r = random ?? Random();
  final clamped = attempt.clamp(0, 5);
  final base = 1 << clamped;            // 1,2,4,8,16,32
  final capped = base > 30 ? 30 : base; // 1,2,4,8,16,30
  final jitter = 1.0 + (r.nextDouble() - 0.5) * 0.4; // [0.8, 1.2]
  final ms = (capped * 1000 * jitter).round();
  return Duration(milliseconds: ms);
}

/// Supervisor-facing status signals. The caller maps these to
/// CameraConnectionStatus (reconnecting / playing) via onStatusChange.
enum ReconnectStatus { reconnecting, playing }

/// Supervisor-facing event signals. The caller maps these to
/// HealthEventType (reconnectAttempt / reconnectSuccess) via onEvent.
enum ReconnectEventType { reconnectAttempt, reconnectSuccess }

/// D-01/D-02: per-camera reconnect supervisor.
/// - Exponential backoff with ±20% jitter (computeBackoff)
/// - Retry forever — never stops scheduling on its own
/// - Dedups overlapping triggers via inFlight guard (Pattern 3)
/// - Three-layer defensive try/catch so timer exceptions NEVER kill the loop
///
/// Integration:
/// - `onAttempt(cameraId)` is the caller-provided reconnect action
///   (typically: player.stop() + _applyPlaybackTuning() + player.open()).
///   It MAY throw; supervisor schedules the next attempt on failure.
/// - `onStatusChange(cameraId, reconnecting|playing)` lets the caller
///   flip UI state via the existing `copyWithCamera` pattern.
/// - `onEvent(type, cameraId, detail)` emits health events
///   (typically forwards to healthEventsProvider.notifier.record).
class ReconnectSupervisor {
  ReconnectSupervisor({
    required this.onAttempt,
    required this.onStatusChange,
    required this.onEvent,
    Random? random,
  }) : _random = random ?? Random();

  final Future<void> Function(String cameraId) onAttempt;
  final void Function(String cameraId, ReconnectStatus status) onStatusChange;
  final void Function(ReconnectEventType type, String cameraId, String? detail)
      onEvent;
  final Random _random;
  final Map<String, _ReconnectState> _perCamera = {};

  /// Dedup-protected entry point (D-03 triggers all route here).
  /// Schedules a retry with computed backoff unless one is already in-flight
  /// OR a retry is already scheduled (Pattern 3 dedup guard).
  Future<void> requestReconnect(
    String cameraId, {
    required String cause,
    bool immediate = false,
  }) async {
    final st = _perCamera.putIfAbsent(cameraId, () => _ReconnectState());
    // Dedup: suppress if an attempt is running OR a retry is already scheduled.
    // This prevents overlapping triggers (stream.error + zombie + wifi) from
    // each scheduling their own parallel retry timers.
    if (st.inFlight || (st.retryTimer?.isActive ?? false)) {
      appLog('RECONNECT', '$cameraId: suppressed duplicate ($cause)');
      return;
    }
    st.inFlight = true;
    st.firstDropAt ??= DateTime.now();
    onStatusChange(cameraId, ReconnectStatus.reconnecting);
    onEvent(
      ReconnectEventType.reconnectAttempt,
      cameraId,
      'attempt ${st.attempt} (cause=$cause)',
    );

    try {
      if (immediate) {
        // WiFi-reconnect trigger (D-03): bypass backoff — network just came back.
        st.retryTimer?.cancel();
        await _attemptReconnect(cameraId);
      } else {
        _scheduleRetry(cameraId, computeBackoff(st.attempt, random: _random));
      }
    } catch (_) {
      // _attemptReconnect already rescheduled via _scheduleRetry on failure.
      // Swallow so the requestReconnect future completes cleanly.
    } finally {
      st.inFlight = false;
    }
  }

  /// THREE-LAYER defensive recurring timer (Pattern 4, CLAUDE.md §Conventions).
  /// Inner try/catch recovers from attempt failures.
  /// Outer try/catch protects the scheduling call itself (D-02 retry-forever).
  void _scheduleRetry(String cameraId, Duration delay) {
    final st = _perCamera.putIfAbsent(cameraId, () => _ReconnectState());
    st.retryTimer?.cancel();
    appLog(
      'RECONNECT',
      '$cameraId: scheduling retry in ${delay.inMilliseconds}ms (attempt=${st.attempt})',
    );
    st.retryTimer = Timer(delay, () async {
      try {
        await _attemptReconnect(cameraId);
      } catch (e, stack) {
        appLog('RECONNECT', '$cameraId: retry crashed: $e\n$stack');
        // D-02: retry forever. Schedule the NEXT attempt even after a crash.
        try {
          // _attemptReconnect already incremented attempt + called _scheduleRetry
          // before rethrowing on failure. No second schedule needed here.
        } catch (_) {
          // Double-catch: if scheduling itself throws, the stream.error listener
          // will kick the supervisor again. Loop MUST NOT die here.
          appLog(
            'RECONNECT',
            '$cameraId: scheduling itself failed — relying on stream.error fallback',
          );
        }
      }
    });
  }

  Future<void> _attemptReconnect(String cameraId) async {
    final st = _perCamera.putIfAbsent(cameraId, () => _ReconnectState());
    try {
      await onAttempt(cameraId);
      // Success: reset backoff, record recovery.
      st.attempt = 0;
      st.firstDropAt = null;
      onStatusChange(cameraId, ReconnectStatus.playing);
      onEvent(ReconnectEventType.reconnectSuccess, cameraId, null);
      appLog('RECONNECT', '$cameraId: reconnect succeeded');
    } catch (e) {
      // Failure: increment attempt and schedule the next retry (D-02).
      st.attempt += 1;
      appLog('RECONNECT', '$cameraId: attempt failed ($e), scheduling next');
      try {
        _scheduleRetry(cameraId, computeBackoff(st.attempt, random: _random));
      } catch (schedErr) {
        // Triple-layer defense: if scheduling itself fails, log and rely on
        // the stream.error listener in AudioPlayerNotifier to re-kick us.
        appLog(
          'RECONNECT',
          '$cameraId: scheduling itself failed ($schedErr) — relying on stream.error fallback',
        );
      }
      rethrow; // Let outer try/catch in _scheduleRetry log the stack too.
    }
  }

  /// Cancel all timers (retry + alert) and forget all per-camera state.
  /// MUST be called from stopMonitoring AND onDispose.
  void cancelAll() {
    for (final st in _perCamera.values) {
      st.retryTimer?.cancel();
      st.alertTimer?.cancel();
    }
    _perCamera.clear();
    appLog('RECONNECT', 'Supervisor cancelled all timers');
  }

  /// Test hook: inspect pending retry state.
  int attemptCount(String cameraId) => _perCamera[cameraId]?.attempt ?? 0;
  bool hasPendingRetry(String cameraId) =>
      (_perCamera[cameraId]?.retryTimer?.isActive ?? false);
}
