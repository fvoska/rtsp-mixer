/// A stream URL candidate with a human-readable label for logs.
typedef StreamCandidate = ({String label, String url});

/// Build the ordered candidate list for [quality]. Candidates are tried in
/// order until one opens (see `_openFirstCandidate`):
///
///  1. `local` — the address the camera was configured with (manual) or the
///     API URL re-pointed at the console address (Unifi).
///  2. `remote` — the local URL re-pointed at the globally configured remote
///     (VPN/Tailscale) host. Applies to Unifi AND manual cameras — covers
///     NVR-style setups where every stream is served from one host.
///  3. `override` — the camera's own remote URL (manual cameras only), for
///     cameras whose remote address doesn't follow the global host swap.
///
/// Empty URLs and duplicates of an earlier candidate are dropped. When the
/// maps yield nothing, falls back to [activeUrl] so a (re)connect always has
/// something to try.
///
/// Defensive by contract (CLAUDE.md): never throws.
List<StreamCandidate> orderedStreamCandidates({
  required Map<String, String> local,
  required Map<String, String> remote,
  required Map<String, String> cameraRemote,
  required String? quality,
  String? activeUrl,
}) {
  final candidates = <StreamCandidate>[];
  try {
    void add(String label, String? url) {
      if (url == null || url.isEmpty) return;
      if (candidates.any((c) => c.url == url)) return;
      candidates.add((label: label, url: url));
    }

    if (quality != null) {
      add('local', local[quality]);
      add('remote', remote[quality]);
      add('override', cameraRemote[quality]);
    }
    if (candidates.isEmpty) add('active', activeUrl);
  } catch (_) {
    // Never throw — candidate building must not kill a (re)connect attempt.
  }
  return candidates;
}
