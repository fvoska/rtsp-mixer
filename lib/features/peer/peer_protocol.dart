/// Wire-level constants shared by the host (phone-as-camera) and the monitor
/// (the phone that listens). Both ends ship in the same app, so bumping
/// [kPeerProtocolVersion] is how an incompatible change is negotiated: a
/// monitor refuses to pair with a host reporting a different version.
library;

/// Protocol version carried in discovery replies, `/info` and QR payloads.
const int kPeerProtocolVersion = 1;

/// Well-known UDP port the host's discovery beacon listens on. Fixed so a
/// monitor can probe without any prior knowledge of the host.
const int kPeerDiscoveryPort = 47830;

/// Preferred TCP port for the host's HTTP server. Falls back to an ephemeral
/// port when taken; the real port is advertised via discovery and the QR.
const int kPeerPreferredHttpPort = 47831;

/// URL path prefix for every host endpoint.
const String kPeerApiPrefix = '/roomtone/v1';

/// Unauthenticated: identifies a Roomtone host (name, id, version).
const String kPeerInfoPath = '$kPeerApiPrefix/info';

/// POST {code, clientName, clientId} → {token, …}.
const String kPeerPairPath = '$kPeerApiPrefix/pair';

/// Authenticated (token query param): live level + listener count.
const String kPeerStatusPath = '$kPeerApiPrefix/status';

/// Authenticated (token query param): endless WAV audio stream.
const String kPeerAudioPath = '$kPeerApiPrefix/audio.wav';

/// Query parameter that carries the bearer token. A query parameter (rather
/// than a header) is deliberate: the stream URL is handed to libmpv, and the
/// existing candidate/reconnect machinery works purely on URLs.
const String kPeerTokenParam = 'token';

/// Microphone capture format. Mono 16 kHz PCM16 is 256 kbit/s — trivial on a
/// LAN — and covers everything a baby monitor needs to hear.
const int kPeerSampleRate = 16000;
const int kPeerChannels = 1;
const int kPeerBitsPerSample = 16;

/// Bytes per second of the capture format; used for backlog accounting.
const int kPeerBytesPerSecond =
    kPeerSampleRate * kPeerChannels * (kPeerBitsPerSample ~/ 8);

/// Discovery datagram markers.
const String kDiscoveryProbeType = 'probe';
const String kDiscoveryReplyType = 'host';
const String kDiscoveryAppTag = 'roomtone';
