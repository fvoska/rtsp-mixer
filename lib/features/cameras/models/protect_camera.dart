/// Where a camera came from.
///
/// [unifi] cameras are discovered from the Unifi Protect integration API.
/// [manual] cameras are RTSP/RTSPS URLs entered by the user and persisted
/// locally — they work with or without a Unifi console.
/// [peer] cameras are other phones running Roomtone in host mode, paired
/// over the LAN; their stream URL is the host's HTTP WAV endpoint.
enum CameraSource { unifi, manual, peer }

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

  /// Where this camera came from (Unifi API, manually entered URL, or a
  /// paired phone).
  final CameraSource source;

  /// Stable id of the paired phone (peer cameras only). Lets the monitor
  /// re-resolve the host's current LAN address via discovery when its DHCP
  /// lease changes, and de-duplicates re-pairing with the same phone.
  final String? peerHostId;

  /// Available RTSPS stream URLs keyed by quality (high, medium, low).
  /// Manual cameras store their single URL under the `stream` key.
  final Map<String, String> rtspsStreamUrls;

  /// Optional remote (VPN/Tailscale) stream URL for manual cameras, used
  /// verbatim as the last playback candidate — after the local URL and after
  /// the global remote-host rewrite. Covers cameras whose remote address
  /// doesn't follow the global host swap. Always null for Unifi cameras —
  /// their remote candidates are derived from the console's remote host at
  /// playback time.
  final String? remoteUrl;

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
    this.remoteUrl,
    this.peerHostId,
  });

  /// Build a manually-entered camera from a raw RTSP/RTSPS URL. The URL is
  /// used verbatim at playback time (no Unifi port/scheme rewriting), so
  /// the user is responsible for providing a working stream URL.
  factory ProtectCamera.manual({
    required String id,
    required String url,
    String? name,
    String? remoteUrl,
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
        remoteUrl: remoteUrl,
      );

  /// A paired phone running Roomtone in host mode. [url] is the host's
  /// stream URL (address, port and bearer token); it is rebuilt by the
  /// monitor whenever discovery reports the host at a new address.
  factory ProtectCamera.peer({
    required String id,
    required String url,
    required String hostId,
    String? name,
  }) =>
      ProtectCamera(
        id: id,
        name: name,
        // Reachability is only known at connect time, like manual cameras.
        state: 'CONNECTED',
        isMicEnabled: true,
        rtspsStreamUrls: {'stream': url},
        source: CameraSource.peer,
        peerHostId: hostId,
      );

  bool get isConnected => state == 'CONNECTED';

  bool get isManual => source == CameraSource.manual;

  bool get isPeer => source == CameraSource.peer;

  bool get isUnifi => source == CameraSource.unifi;

  /// True for cameras the user added on this device (manual URLs and paired
  /// phones) — the ones that can be deleted from the picker and whose URLs
  /// are played verbatim (no Unifi RTSPS↔RTSP rewriting).
  bool get isLocallyManaged => source != CameraSource.unifi;

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

  /// Sentinel distinguishing "not passed" from an explicit null so
  /// [copyWith] can both preserve and clear [remoteUrl].
  static const Object _unset = Object();

  ProtectCamera copyWith({
    Map<String, String>? rtspsStreamUrls,
    Object? remoteUrl = _unset,
  }) =>
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
        remoteUrl:
            identical(remoteUrl, _unset) ? this.remoteUrl : remoteUrl as String?,
        peerHostId: peerHostId,
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
        'remoteUrl': remoteUrl,
        'peerHostId': peerHostId,
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
        // Absent or unknown `source` (legacy cache, or a newer build's
        // value) → unifi rather than a throw out of the whole decode.
        source: _sourceFromName(json['source']),
        // Absent key (legacy JSON from before remote URLs) → null.
        remoteUrl: json['remoteUrl'] as String?,
        peerHostId: json['peerHostId'] as String?,
      );

  static CameraSource _sourceFromName(Object? raw) {
    if (raw is! String) return CameraSource.unifi;
    for (final s in CameraSource.values) {
      if (s.name == raw) return s;
    }
    return CameraSource.unifi;
  }
}
