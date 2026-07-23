/// Connection status for a single camera's RTSP stream.
enum CameraConnectionStatus { idle, connecting, playing, reconnecting, error }

/// Stream technical info collected from player events.
class StreamInfo {
  final String? audioCodec;
  final String? audioFormat;
  final String? videoCodec;
  final int? sampleRate;
  final String? channels;
  final int? audioBitrate;
  final int? videoBitrate;
  final int? width;
  final int? height;
  final double? fps;

  const StreamInfo({
    this.audioCodec,
    this.audioFormat,
    this.videoCodec,
    this.sampleRate,
    this.channels,
    this.audioBitrate,
    this.videoBitrate,
    this.width,
    this.height,
    this.fps,
  });

  /// Update with new values. Pass explicit null to clear a field;
  /// omit a field to keep the existing value.
  StreamInfo merge({
    Object? audioCodec = _sentinel,
    Object? audioFormat = _sentinel,
    Object? videoCodec = _sentinel,
    Object? sampleRate = _sentinel,
    Object? channels = _sentinel,
    Object? audioBitrate = _sentinel,
    Object? videoBitrate = _sentinel,
    Object? width = _sentinel,
    Object? height = _sentinel,
    Object? fps = _sentinel,
  }) =>
      StreamInfo(
        audioCodec: audioCodec == _sentinel ? this.audioCodec : audioCodec as String?,
        audioFormat: audioFormat == _sentinel ? this.audioFormat : audioFormat as String?,
        videoCodec: videoCodec == _sentinel ? this.videoCodec : videoCodec as String?,
        sampleRate: sampleRate == _sentinel ? this.sampleRate : sampleRate as int?,
        channels: channels == _sentinel ? this.channels : channels as String?,
        audioBitrate: audioBitrate == _sentinel ? this.audioBitrate : audioBitrate as int?,
        videoBitrate: videoBitrate == _sentinel ? this.videoBitrate : videoBitrate as int?,
        width: width == _sentinel ? this.width : width as int?,
        height: height == _sentinel ? this.height : height as int?,
        fps: fps == _sentinel ? this.fps : fps as double?,
      );

  static const Object _sentinel = Object();
}

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
  final String? activeQuality;
  final String? activeStreamUrl;
  final Map<String, String> availableQualities;

  /// Remote (VPN/Tailscale) stream URL per quality, parallel to
  /// [availableQualities] — the local URL re-pointed at the globally
  /// configured remote host. Empty when no remote address is configured.
  /// Playback always tries the local candidate first and falls back to the
  /// remote one; [activeStreamUrl] reflects whichever URL is actually in use.
  final Map<String, String> remoteQualities;

  /// Per-camera remote URL override (manual cameras), parallel to
  /// [availableQualities] and tried after [remoteQualities]. Covers cameras
  /// whose remote address doesn't follow the global host swap. Empty for
  /// Unifi cameras and manual cameras without a remote URL.
  final Map<String, String> overrideQualities;
  final StreamInfo streamInfo;
  final double audioLevel; // 0.0..1.0 absolute pseudo-SPL, log-mapped from AAC encoded bitrate
  final double audioActivity; // 0.0..1.0 recent variation — peak-to-trough of levelHistory over ~5 s
  final double silenceDuration; // seconds of continuous silence

  /// Rolling pseudo-SPL samples, oldest first, capacity
  /// `kLevelHistoryCapacity` — feeds the waveform chart and the variation
  /// statistic.
  final List<double> levelHistory;

  // Camera device info from Unifi API.
  final String? mac;
  final String? modelKey;
  final int? micVolume;

  /// True when this camera came from a manually-entered RTSP URL rather than
  /// the Unifi API. Drives the source badge in the UI.
  final bool isManual;

  const CameraAudioState({
    required this.cameraId,
    required this.cameraName,
    this.volume = 100.0,
    this.pan = 0.0,
    this.isMuted = false,
    this.preMuteVolume = 100.0,
    this.connectionStatus = CameraConnectionStatus.idle,
    this.errorMessage,
    this.activeQuality,
    this.activeStreamUrl,
    this.availableQualities = const {},
    this.remoteQualities = const {},
    this.overrideQualities = const {},
    this.streamInfo = const StreamInfo(),
    this.audioLevel = 0.0,
    this.audioActivity = 0.0,
    this.silenceDuration = 0.0,
    this.levelHistory = const [],
    this.mac,
    this.modelKey,
    this.micVolume,
    this.isManual = false,
  });

  CameraAudioState copyWith({
    double? volume,
    double? pan,
    bool? isMuted,
    double? preMuteVolume,
    CameraConnectionStatus? connectionStatus,
    String? errorMessage,
    String? activeQuality,
    String? activeStreamUrl,
    Map<String, String>? availableQualities,
    Map<String, String>? remoteQualities,
    Map<String, String>? overrideQualities,
    StreamInfo? streamInfo,
    double? audioLevel,
    double? audioActivity,
    double? silenceDuration,
    List<double>? levelHistory,
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
        activeQuality: activeQuality ?? this.activeQuality,
        activeStreamUrl: activeStreamUrl ?? this.activeStreamUrl,
        availableQualities: availableQualities ?? this.availableQualities,
        remoteQualities: remoteQualities ?? this.remoteQualities,
        overrideQualities: overrideQualities ?? this.overrideQualities,
        streamInfo: streamInfo ?? this.streamInfo,
        audioLevel: audioLevel ?? this.audioLevel,
        audioActivity: audioActivity ?? this.audioActivity,
        silenceDuration: silenceDuration ?? this.silenceDuration,
        // Passing `const []` explicitly clears the history (the reconnect
        // path relies on this); passing null keeps the existing samples.
        levelHistory: levelHistory ?? this.levelHistory,
        mac: mac,
        modelKey: modelKey,
        micVolume: micVolume,
        isManual: isManual,
      );

  double get effectiveVolume => isMuted ? 0.0 : volume;
  bool get isLive => connectionStatus == CameraConnectionStatus.playing;
  bool get isError => connectionStatus == CameraConnectionStatus.error;
  bool get isReconnecting => connectionStatus == CameraConnectionStatus.reconnecting;
  bool get isSuspiciouslySilent => isLive && silenceDuration > 10.0;
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

  MonitoringState copyWith({List<CameraAudioState>? cameras}) =>
      MonitoringState(cameras: cameras ?? this.cameras);

  bool get allLive => cameras.isNotEmpty && cameras.every((c) => c.isLive);
  bool get anyError => cameras.any((c) => c.isError);
}
