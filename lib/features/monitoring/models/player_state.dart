/// Connection status for a single camera's RTSP stream.
enum CameraConnectionStatus { idle, connecting, playing, error }

/// Per-camera audio state. Immutable value object.
class CameraAudioState {
  final String cameraId;
  final String cameraName;
  final double volume; // 0.0 to 100.0
  final double pan; // -1.0 (left) to 1.0 (right)
  final bool isMuted;
  final double preMuteVolume; // volume before mute (for restore)
  final CameraConnectionStatus connectionStatus;
  final String? errorMessage;

  const CameraAudioState({
    required this.cameraId,
    required this.cameraName,
    this.volume = 100.0,
    this.pan = 0.0,
    this.isMuted = false,
    this.preMuteVolume = 100.0,
    this.connectionStatus = CameraConnectionStatus.idle,
    this.errorMessage,
  });

  CameraAudioState copyWith({
    double? volume,
    double? pan,
    bool? isMuted,
    double? preMuteVolume,
    CameraConnectionStatus? connectionStatus,
    String? errorMessage,
  }) =>
      CameraAudioState(
        cameraId: cameraId,
        cameraName: cameraName,
        volume: volume ?? this.volume,
        pan: pan ?? this.pan,
        isMuted: isMuted ?? this.isMuted,
        preMuteVolume: preMuteVolume ?? this.preMuteVolume,
        connectionStatus: connectionStatus ?? this.connectionStatus,
        errorMessage: errorMessage,
      );

  /// The effective volume sent to Player.setVolume().
  /// Returns 0.0 when muted, otherwise the volume value.
  double get effectiveVolume => isMuted ? 0.0 : volume;

  bool get isLive => connectionStatus == CameraConnectionStatus.playing;
  bool get isError => connectionStatus == CameraConnectionStatus.error;
}

/// State for the entire monitoring session (both cameras).
class MonitoringState {
  final List<CameraAudioState> cameras;

  const MonitoringState({this.cameras = const []});

  MonitoringState copyWithCamera(int index, CameraAudioState camera) {
    final updated = List<CameraAudioState>.from(cameras);
    updated[index] = camera;
    return MonitoringState(cameras: updated);
  }

  bool get allLive => cameras.isNotEmpty && cameras.every((c) => c.isLive);
  bool get anyError => cameras.any((c) => c.isError);
}
