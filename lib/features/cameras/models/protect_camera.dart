/// Camera from the official Protect API (integration/v1/cameras).
class ProtectCamera {
  final String id;
  final String? name;
  final String state;
  final bool isMicEnabled;
  final String? mac;
  final String? modelKey;
  final int? micVolume;

  /// Available RTSPS stream URLs keyed by quality (high, medium, low).
  final Map<String, String> rtspsStreamUrls;

  const ProtectCamera({
    required this.id,
    this.name,
    required this.state,
    this.isMicEnabled = false,
    this.mac,
    this.modelKey,
    this.micVolume,
    this.rtspsStreamUrls = const {},
  });

  bool get isConnected => state == 'CONNECTED';

  /// The default stream URL: prefer medium, fall back to high, then low.
  String? get defaultStreamUrl =>
      rtspsStreamUrls['medium'] ??
      rtspsStreamUrls['high'] ??
      rtspsStreamUrls['low'];

  /// The default quality key matching defaultStreamUrl.
  String? get defaultQuality {
    if (rtspsStreamUrls.containsKey('medium')) return 'medium';
    if (rtspsStreamUrls.containsKey('high')) return 'high';
    if (rtspsStreamUrls.containsKey('low')) return 'low';
    return null;
  }

  ProtectCamera copyWith({Map<String, String>? rtspsStreamUrls}) =>
      ProtectCamera(
        id: id,
        name: name,
        state: state,
        isMicEnabled: isMicEnabled,
        mac: mac,
        modelKey: modelKey,
        micVolume: micVolume,
        rtspsStreamUrls: rtspsStreamUrls ?? this.rtspsStreamUrls,
      );

  factory ProtectCamera.fromJson(Map<String, dynamic> json) => ProtectCamera(
        id: json['id'] as String,
        name: json['name'] as String?,
        state: json['state'] as String? ?? 'DISCONNECTED',
        isMicEnabled: json['isMicEnabled'] as bool? ?? false,
        mac: json['mac'] as String?,
        modelKey: json['modelKey'] as String?,
        micVolume: json['micVolume'] as int?,
      );
}
