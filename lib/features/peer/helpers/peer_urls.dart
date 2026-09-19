import '../peer_protocol.dart';

/// URL construction/parsing for a paired phone camera.
///
/// The monitor stores the host's address, port and token separately and
/// rebuilds the stream URL whenever discovery reports a new address, so a
/// DHCP lease change never strands a paired camera. Defensive by contract:
/// nothing here throws.

/// Wrap an IPv6 literal in brackets for use in a URL host position.
String _urlHost(String address) =>
    address.contains(':') && !address.startsWith('[') ? '[$address]' : address;

Uri _endpoint(String address, int port, String path, [String? token]) => Uri(
      scheme: 'http',
      host: _urlHost(address),
      port: port,
      path: path,
      queryParameters: token == null ? null : {kPeerTokenParam: token},
    );

/// The endless-WAV stream URL libmpv opens.
String peerStreamUrl(String address, int port, String token) =>
    _endpoint(address, port, kPeerAudioPath, token).toString();

/// The host's level/listener status endpoint.
String peerStatusUrl(String address, int port, String token) =>
    _endpoint(address, port, kPeerStatusPath, token).toString();

/// Unauthenticated identity endpoint.
String peerInfoUrl(String address, int port) =>
    _endpoint(address, port, kPeerInfoPath).toString();

String peerPairUrl(String address, int port) =>
    _endpoint(address, port, kPeerPairPath).toString();

/// Derive the status URL from a stored stream URL (same host/port/token).
/// Returns null when [streamUrl] is not a peer stream URL.
String? peerStatusUrlFromStream(String? streamUrl) {
  if (streamUrl == null) return null;
  try {
    final uri = Uri.parse(streamUrl);
    if (uri.path != kPeerAudioPath) return null;
    final token = uri.queryParameters[kPeerTokenParam];
    if (token == null || token.isEmpty) return null;
    return uri.replace(path: kPeerStatusPath).toString();
  } catch (_) {
    return null;
  }
}

/// True when [url] points at a Roomtone host's audio endpoint.
bool isPeerStreamUrl(String? url) {
  if (url == null) return false;
  try {
    final uri = Uri.parse(url);
    return uri.scheme == 'http' && uri.path == kPeerAudioPath;
  } catch (_) {
    return false;
  }
}

/// Re-point a peer stream URL at [address]:[port], keeping the token. Falls
/// back to [url] unchanged on any parse failure.
String repointPeerUrl(String url, String address, int port) {
  try {
    final uri = Uri.parse(url);
    return uri.replace(host: _urlHost(address), port: port).toString();
  } catch (_) {
    return url;
  }
}

/// Human-friendly "192.168.1.20:47831" label for a peer URL (no token).
String peerAddressLabel(String? url) {
  if (url == null) return '';
  try {
    final uri = Uri.parse(url);
    return '${uri.host}:${uri.port}';
  } catch (_) {
    return '';
  }
}
