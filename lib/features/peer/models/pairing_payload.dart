import '../peer_protocol.dart';

/// Contents of the pairing QR code the host displays.
///
/// Encoded as a `roomtone://pair?...` URI so that a scanned string is
/// self-describing and a future `roomtone://` deep link could reuse it. The
/// address is the host's current LAN IP; the monitor still re-resolves the
/// host by [hostId] via discovery, so a stale IP in a QR degrades to a slower
/// first connection, not a failed one.
class PairingPayload {
  const PairingPayload({
    required this.hostId,
    required this.hostName,
    required this.address,
    required this.port,
    required this.code,
    this.protocol = kPeerProtocolVersion,
  });

  final String hostId;
  final String hostName;
  final String address;
  final int port;
  final String code;
  final int protocol;

  static const scheme = 'roomtone';
  static const host = 'pair';

  Uri toUri() => Uri(
        scheme: scheme,
        host: host,
        queryParameters: {
          'v': '$protocol',
          'id': hostId,
          'n': hostName,
          'h': address,
          'p': '$port',
          'c': code,
        },
      );

  @override
  String toString() => toUri().toString();

  /// Parse a scanned QR string. Returns null for anything that is not a
  /// well-formed Roomtone pairing URI — a scanner sees arbitrary codes
  /// (Wi-Fi QR, URLs) and none of them may throw out of the scan callback.
  static PairingPayload? tryParse(String? raw) {
    if (raw == null) return null;
    try {
      final uri = Uri.tryParse(raw.trim());
      if (uri == null) return null;
      if (uri.scheme.toLowerCase() != scheme) return null;
      if (uri.host.toLowerCase() != host) return null;
      final q = uri.queryParameters;
      final id = q['id'];
      final address = q['h'];
      final code = q['c'];
      final port = int.tryParse(q['p'] ?? '');
      final protocol = int.tryParse(q['v'] ?? '') ?? kPeerProtocolVersion;
      if (id == null || id.isEmpty) return null;
      if (address == null || address.isEmpty) return null;
      if (code == null || code.isEmpty) return null;
      if (port == null || port <= 0 || port > 65535) return null;
      return PairingPayload(
        hostId: id,
        hostName: q['n'] ?? 'Phone camera',
        address: address,
        port: port,
        code: code,
        protocol: protocol,
      );
    } catch (_) {
      return null;
    }
  }

  bool get isSupportedProtocol => protocol == kPeerProtocolVersion;
}
