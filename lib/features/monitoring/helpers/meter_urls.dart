import 'rtsp_url.dart';

/// Quality preference for the analyzer sidecar: loudness needs the fewest
/// bytes, so the low-quality stream is analyzed regardless of what the
/// playback path is tuned to.
const kMeterQualityPreference = ['low', 'medium', 'high'];

/// Build the ordered candidate URL list for a camera's level-meter sidecar.
///
/// Mirrors `orderedStreamCandidates` (local → remote → override) but with two
/// sidecar-specific twists:
///
///  - Always prefers the LOW quality stream (see [kMeterQualityPreference]);
///    falls back through the preference list, then any available key.
///  - Unifi URLs (non-manual) are rewritten to plain RTSP on :7447 via
///    [rtspsToRtsp] — media3's RTSP stack cannot decrypt SRTP, and plain
///    RTSP is the transport the Windows playback path already proves works.
///    Manual camera URLs pass through verbatim (an rtsps:// manual URL is
///    attempted natively over TLS, best-effort).
///
/// Defensive by contract (CLAUDE.md): never throws; returns an empty list
/// when nothing usable exists (the caller simply skips the sidecar and the
/// meter falls back to the bitrate proxy).
List<String> meterStreamUrls({
  required Map<String, String> local,
  required Map<String, String> remote,
  required Map<String, String> cameraRemote,
  required bool isManual,
}) {
  final urls = <String>[];
  try {
    String? quality;
    for (final q in kMeterQualityPreference) {
      if ((local[q] ?? remote[q] ?? cameraRemote[q]) != null) {
        quality = q;
        break;
      }
    }
    quality ??= local.keys.firstOrNull ??
        remote.keys.firstOrNull ??
        cameraRemote.keys.firstOrNull;
    if (quality == null) return urls;

    void add(String? url) {
      if (url == null || url.isEmpty) return;
      final resolved = isManual ? url : rtspsToRtsp(url);
      if (!urls.contains(resolved)) urls.add(resolved);
    }

    add(local[quality]);
    add(remote[quality]);
    add(cameraRemote[quality]);
  } catch (_) {
    // Never throw — a malformed URL map just means no native metering.
  }
  return urls;
}
