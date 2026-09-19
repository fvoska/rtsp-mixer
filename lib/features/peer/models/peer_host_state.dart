import 'paired_client.dart';

enum PeerHostStatus { idle, starting, running, error }

/// Everything the host screen shows. Immutable value object.
class PeerHostState {
  const PeerHostState({
    this.status = PeerHostStatus.idle,
    this.loaded = false,
    this.hostId = '',
    this.name = 'Phone camera',
    this.code = '',
    this.addresses = const [],
    this.port,
    this.level = 0.0,
    this.listeners = 0,
    this.pairedClients = const [],
    this.autoResume = false,
    this.discoveryActive = false,
    this.micActive = false,
    this.errorMessage,
    this.lastPairingNote,
    this.startedAt,
  });

  final PeerHostStatus status;

  /// Config has been read from storage (name, paired devices, auto-resume).
  final bool loaded;
  final String hostId;
  final String name;

  /// Current pairing code; empty when not running.
  final String code;

  /// LAN IPv4 addresses this phone can be reached on, best first.
  final List<String> addresses;
  final int? port;

  /// Smoothed microphone level 0..1.
  final double level;
  final int listeners;
  final List<PairedClient> pairedClients;

  /// Host mode resumes on the next app launch (set while hosting).
  final bool autoResume;
  final bool discoveryActive;

  /// The microphone stream is currently delivering data.
  final bool micActive;
  final String? errorMessage;

  /// One-line note about the most recent pairing attempt, for the UI.
  final String? lastPairingNote;
  final DateTime? startedAt;

  bool get isRunning => status == PeerHostStatus.running;
  bool get isBusy => status == PeerHostStatus.starting;
  String? get primaryAddress => addresses.isEmpty ? null : addresses.first;

  static const Object _unset = Object();

  PeerHostState copyWith({
    PeerHostStatus? status,
    bool? loaded,
    String? hostId,
    String? name,
    String? code,
    List<String>? addresses,
    Object? port = _unset,
    double? level,
    int? listeners,
    List<PairedClient>? pairedClients,
    bool? autoResume,
    bool? discoveryActive,
    bool? micActive,
    Object? errorMessage = _unset,
    Object? lastPairingNote = _unset,
    Object? startedAt = _unset,
  }) =>
      PeerHostState(
        status: status ?? this.status,
        loaded: loaded ?? this.loaded,
        hostId: hostId ?? this.hostId,
        name: name ?? this.name,
        code: code ?? this.code,
        addresses: addresses ?? this.addresses,
        port: identical(port, _unset) ? this.port : port as int?,
        level: level ?? this.level,
        listeners: listeners ?? this.listeners,
        pairedClients: pairedClients ?? this.pairedClients,
        autoResume: autoResume ?? this.autoResume,
        discoveryActive: discoveryActive ?? this.discoveryActive,
        micActive: micActive ?? this.micActive,
        errorMessage: identical(errorMessage, _unset)
            ? this.errorMessage
            : errorMessage as String?,
        lastPairingNote: identical(lastPairingNote, _unset)
            ? this.lastPairingNote
            : lastPairingNote as String?,
        startedAt:
            identical(startedAt, _unset) ? this.startedAt : startedAt as DateTime?,
      );
}
