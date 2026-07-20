/// Where a camera came from.
///
/// [unifi] cameras are discovered from the Unifi Protect integration API.
/// [manual] cameras are RTSP/RTSPS URLs entered by the user and persisted
/// locally — they work with or without a Unifi console.
enum CameraSource { unifi, manual }

/// A camera the app can monitor. Historically only Unifi Protect cameras
/// (integration/v1/cameras), now also user-entered manual RTSP streams —
/// see [CameraSource].
class ProtectCamera {
  final String id;
  final String? name;
  final String state;
  final bool isMicEnabled;
  final String? mac;
  final String? modelKey;
  final int? micVolume;

  /// Where this camera came from (Unifi API vs manually entered URL).
  final CameraSource source;

  /// Available RTSPS stream URLs keyed by quality (high, medium, low).
  /// Manual cameras store their single URL under the `stream` key.
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
    this.source = CameraSource.unifi,
  });

  /// Build a manually-entered camera from a raw RTSP/RTSPS URL. The URL is
  /// used verbatim at playback time (no Unifi port/scheme rewriting), so
  /// the user is responsible for providing a working stream URL.
  factory ProtectCamera.manual({
    required String id,
    required String url,
    String? name,
  }) =>
      ProtectCamera(
        id: id,
        name: name,
        // We can't probe a manual stream's state, so treat it as reachable —
        // failures surface at connect time via the player's error stream.
        state: 'CONNECTED',
        // Assume audio is present; a manual RTSP stream has no mic-enabled flag
        // and we must not show a misleading "mic disabled" warning.
        isMicEnabled: true,
        rtspsStreamUrls: {'stream': url},
        source: CameraSource.manual,
      );

  bool get isConnected => state == 'CONNECTED';

  bool get isManual => source == CameraSource.manual;

  /// The default stream URL: prefer lowest quality since audio is identical
  /// across all qualities — no point decoding a larger video mux. Falls back
  /// to the first available URL (e.g. a manual camera's single `stream`).
  String? get defaultStreamUrl =>
      rtspsStreamUrls['low'] ??
      rtspsStreamUrls['medium'] ??
      rtspsStreamUrls['high'] ??
      (rtspsStreamUrls.isNotEmpty ? rtspsStreamUrls.values.first : null);

  /// The default quality key matching defaultStreamUrl.
  String? get defaultQuality {
    if (rtspsStreamUrls.containsKey('low')) return 'low';
    if (rtspsStreamUrls.containsKey('medium')) return 'medium';
    if (rtspsStreamUrls.containsKey('high')) return 'high';
    return rtspsStreamUrls.keys.isNotEmpty ? rtspsStreamUrls.keys.first : null;
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
        source: source,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'state': state,
        'isMicEnabled': isMicEnabled,
        'mac': mac,
        'modelKey': modelKey,
        'micVolume': micVolume,
        'rtspsStreamUrls': rtspsStreamUrls,
        'source': source.name,
      };

  factory ProtectCamera.fromJson(Map<String, dynamic> json) => ProtectCamera(
        id: json['id'] as String,
        name: json['name'] as String?,
        state: json['state'] as String? ?? 'DISCONNECTED',
        isMicEnabled: json['isMicEnabled'] as bool? ?? false,
        mac: json['mac'] as String?,
        modelKey: json['modelKey'] as String?,
        micVolume: json['micVolume'] as int?,
        rtspsStreamUrls: (json['rtspsStreamUrls'] as Map<String, dynamic>?)
                ?.map((k, v) => MapEntry(k, v as String)) ??
            const {},
        // Absent `source` (legacy cache from before manual cameras) → unifi.
        source: (json['source'] as String?) == 'manual'
            ? CameraSource.manual
            : CameraSource.unifi,
      );
}
