/// Event types captured in the overnight health summary (D-15).
enum HealthEventType {
  monitoringStarted,
  monitoringStopped,
  streamStarted,
  streamError,
  reconnectAttempt,
  reconnectSuccess,
  zombieDetected,
  wifiDropped,
  wifiReconnected,
  alertFired,
}

/// Single append-only health event. No copyWith — events are immutable records.
class HealthEvent {
  final DateTime timestamp;
  final HealthEventType type;
  final String? cameraId;   // null for session-wide events
  final String? cameraName; // cached for display (avoid lookup on render)
  final String? detail;     // free-text (error message, attempt number, signal summary)

  const HealthEvent({
    required this.timestamp,
    required this.type,
    this.cameraId,
    this.cameraName,
    this.detail,
  });
}
