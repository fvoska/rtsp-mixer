import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// Constructs unencrypted RTSP URL for a Protect camera.
/// Port 7447 is Unifi Protect's RTSP port (must be enabled per-camera).
String rtspUrl(String nvrHost, String cameraId) {
  final host =
      nvrHost.endsWith('/') ? nvrHost.substring(0, nvrHost.length - 1) : nvrHost;
  return 'rtsp://$host:7447/$cameraId';
}

/// Constructs encrypted RTSPS URL for a Protect camera.
/// Port 7441 is Unifi Protect's RTSPS port with SRTP.
String rtspsUrl(String nvrHost, String cameraId) {
  final host =
      nvrHost.endsWith('/') ? nvrHost.substring(0, nvrHost.length - 1) : nvrHost;
  return 'rtsps://$host:7441/$cameraId?enableSrtp';
}

/// Replace only the host portion of [url] with [newHost], preserving scheme,
/// port, path, and query. Used to derive a remote (VPN/Tailscale) stream
/// candidate from a local-address URL.
///
/// [newHost] is normalized first: surrounding whitespace is trimmed, a pasted
/// scheme prefix (e.g. `https://` or `rtsp://`) is stripped, and trailing
/// slashes are removed.
///
/// Defensive by contract (CLAUDE.md): this helper must NEVER throw. On any
/// parse failure — or when the normalized host is empty — the input [url] is
/// returned unchanged.
String replaceUrlHost(String url, String newHost) {
  try {
    var host = newHost.trim();
    // Strip a pasted scheme prefix like "https://" or "rtsp://".
    final schemeMatch = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.\-]*://').firstMatch(host);
    if (schemeMatch != null) host = host.substring(schemeMatch.end);
    // Strip trailing slashes.
    while (host.endsWith('/')) {
      host = host.substring(0, host.length - 1);
    }
    if (host.isEmpty) return url;

    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return url;
    return uri.replace(host: host).toString();
  } catch (_) {
    // Never throw — a malformed URL simply passes through unchanged.
    return url;
  }
}

/// Convert an RTSPS URL (from the Protect API) to plain RTSP.
/// rtsps://host:7441/alias?enableSrtp → rtsp://host:7447/alias
String rtspsToRtsp(String rtspsUrl) {
  var url = rtspsUrl.replaceFirst('rtsps://', 'rtsp://');
  url = url.replaceFirst(':7441/', ':7447/');
  url = url.replaceFirst(RegExp(r'\?enableSrtp$'), '');
  return url;
}

/// Returns the appropriate URL based on the useRtsp setting.
///
/// On Windows we always force plain RTSP regardless of the setting: the
/// prebuilt media_kit libmpv ships with mbedtls as its TLS backend, and
/// mbedtls cannot negotiate a handshake with Unifi Protect's RTSPS
/// endpoint (Unifi closes the socket mid-handshake — see
/// `MBEDTLS_ERR_NET_SEND_FAILED` / `-0x4e`). Android and macOS builds use
/// OpenSSL / SecureTransport and don't hit this. LAN-only constraint means
/// dropping encryption costs nothing.
bool _forcePlainRtsp() => !kIsWeb && Platform.isWindows;

String resolveStreamUrl(String rtspsUrl, {required bool useRtsp}) {
  return (useRtsp || _forcePlainRtsp()) ? rtspsToRtsp(rtspsUrl) : rtspsUrl;
}
