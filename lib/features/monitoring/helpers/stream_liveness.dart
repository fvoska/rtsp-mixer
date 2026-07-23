import 'package:media_kit/media_kit.dart';

/// Whether [tracks] contains positive evidence that an RTSP session was
/// actually established: any REAL audio or video track in the demuxed
/// track lists.
///
/// media_kit always prepends the `AudioTrack.auto()`/`AudioTrack.no()` and
/// `VideoTrack.auto()`/`VideoTrack.no()` pseudo-tracks, so "real track
/// present" means any entry whose id is outside `{'auto', 'no'}`. A real
/// VIDEO track counts as alive so mic-disabled cameras (no audio track,
/// hence no audioParams ever) still confirm. Subtitle tracks are ignored.
///
/// Used by the stream-liveness confirmation (`_confirmStreamAlive`) as an
/// alive signal: a blackholed TCP connect (e.g. Tailscale exit node
/// silently dropping SYNs to the console's LAN IP) never produces a real
/// track, while a genuinely connected stream does within moments of open().
///
/// Defensive by contract (CLAUDE.md): never throws — returns false on any
/// unexpected failure.
bool hasRealTrack(Tracks tracks) {
  try {
    bool isReal(String id) => id != 'auto' && id != 'no';
    return tracks.audio.any((t) => isReal(t.id)) ||
        tracks.video.any((t) => isReal(t.id));
  } catch (_) {
    // Never throw — broken confirmation plumbing must not disqualify or
    // kill a good stream.
    return false;
  }
}

/// Parse the raw string value of mpv's `track-list/count` property for the
/// liveness-confirmation fallback.
///
/// mpv's track-list contains only real demuxer tracks (no auto/no pseudo
/// entries), so a parsed `0` means no RTSP session was established. Returns
/// null for null, empty, or unparseable input — the "could not determine"
/// signal the caller treats as degrade-to-assume-alive (CLAUDE.md defensive
/// rule: broken confirmation code must never disqualify a good stream).
///
/// Never throws.
int? parseTrackCount(String? raw) => int.tryParse(raw?.trim() ?? '');
