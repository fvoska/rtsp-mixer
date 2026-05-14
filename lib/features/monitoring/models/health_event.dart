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

  /// JSON serialization for session persistence (see SessionHistoryRepository).
  /// Format: {timestamp: ISO8601, type: enum.name, cameraId, cameraName, detail}.
  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'type': type.name,
        if (cameraId != null) 'cameraId': cameraId,
        if (cameraName != null) 'cameraName': cameraName,
        if (detail != null) 'detail': detail,
      };

  /// Parse a HealthEvent from JSON. Throws on malformed input; callers in the
  /// persistence layer should catch and skip the offending event rather than
  /// failing the entire session load (CLAUDE.md: corrupt data → log + degrade).
  factory HealthEvent.fromJson(Map<String, dynamic> json) {
    final ts = DateTime.parse(json['timestamp'] as String);
    final type = HealthEventType.values.byName(json['type'] as String);
    return HealthEvent(
      timestamp: ts,
      type: type,
      cameraId: json['cameraId'] as String?,
      cameraName: json['cameraName'] as String?,
      detail: json['detail'] as String?,
    );
  }
}
