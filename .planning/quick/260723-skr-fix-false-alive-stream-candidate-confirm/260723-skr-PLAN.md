---
phase: quick-260723-skr
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - lib/features/monitoring/helpers/stream_liveness.dart
  - lib/features/monitoring/providers/audio_player_provider.dart
  - test/features/monitoring/helpers/stream_liveness_test.dart
autonomous: true
requirements: [QUICK-260723-SKR]

must_haves:
  truths:
    - "When the local candidate's TCP connect silently blackholes (Tailscale with UDM Pro exit node: SYNs to the console LAN IP are dropped with no RST), the candidate is NOT declared alive on timeout silence — after the initial 4s grace plus one 6s extended grace with zero real tracks and track-list/count parsing to 0, _confirmStreamAlive throws, and _openFirstCandidate moves on to try the remote (ts.net) candidate"
    - "A mic-disabled camera (no audioParams ever, but a real video track appears) is still confirmed alive — a real track in tracks.audio OR tracks.video with id not in {'auto','no'} counts as positive evidence"
    - "If the confirmation plumbing itself fails (tracks subscription error, getProperty throws, track-list/count returns garbage), the check degrades to assume-alive — broken confirmation code can never disqualify or kill a good stream (CLAUDE.md defensive-error-handling rule)"
    - "An error event within either grace window still disqualifies the candidate immediately (existing fast-failure behavior unchanged)"
    - "No exception from the liveness check propagates outside _openFirstCandidate's per-candidate catch — a dead local candidate can never kill the attempt at the remote candidate"
  artifacts:
    - "lib/features/monitoring/helpers/stream_liveness.dart — pure hasRealTrack(Tracks) and parseTrackCount(String?) helpers"
    - "test/features/monitoring/helpers/stream_liveness_test.dart — unit tests for both helpers"
    - "lib/features/monitoring/providers/audio_player_provider.dart — reworked _confirmStreamAlive with tracks listener, two-stage grace, and track-list/count fallback"
  key_links:
    - "_openFirstCandidate → _confirmStreamAlive throw → catch/log → next candidate in orderedStreamCandidates list (this throw path is what makes the remote ts.net candidate get tried)"
    - "player.stream.tracks → hasRealTrack → completer.complete(null) (alive)"
    - "(player.platform as NativePlayer).getProperty('track-list/count') → parseTrackCount → 0 means no RTSP session established"
---

<objective>
Fix the false-alive stream candidate confirmation that breaks monitoring over Tailscale when the UDM Pro is the exit node. `_confirmStreamAlive` currently treats "no signal within the 4s grace" as alive; with an exit node, SYNs to the console's LAN IP are silently dropped (no RST/ICMP), FFmpeg's TCP connect hangs ~2 minutes, no error arrives within 4s, and the dead `local` candidate is falsely declared the winner — the working `remote` (ts.net) candidate is never tried and the zombie watchdog loops the same losing sequence all night.

Purpose: declaring a candidate alive must require positive evidence the RTSP session was actually established (audioParams, a real track, or a nonzero mpv track-list), while confirmation-plumbing failures still degrade to assume-alive per CLAUDE.md.
Output: pure liveness helpers with unit tests, and a reworked `_confirmStreamAlive` with two-stage grace and a `track-list/count` belt-and-braces fallback.
</objective>

<execution_context>
@/home/user/rtsp-mixer/.claude/gsd-core/workflows/execute-plan.md
@/home/user/rtsp-mixer/.claude/gsd-core/templates/summary.md
</execution_context>

<context>
@/home/user/rtsp-mixer/CLAUDE.md
@/home/user/rtsp-mixer/.planning/STATE.md
@lib/features/monitoring/providers/audio_player_provider.dart
@lib/features/monitoring/helpers/stream_candidates.dart
@test/features/monitoring/helpers/stream_candidates_test.dart
</context>

<tasks>

<task type="auto" tdd="true">
  <name>Task 1: Pure liveness helpers — hasRealTrack + parseTrackCount with unit tests</name>
  <files>lib/features/monitoring/helpers/stream_liveness.dart, test/features/monitoring/helpers/stream_liveness_test.dart</files>
  <behavior>
    - hasRealTrack: Tracks with a real audio track (e.g. AudioTrack('1', null, null) alongside the AudioTrack.auto()/AudioTrack.no() pseudo entries) → true
    - hasRealTrack: Tracks with ONLY a real video track (mic-disabled camera: audio list contains only auto/no, video list contains e.g. VideoTrack('1', null, null)) → true
    - hasRealTrack: Tracks containing only the auto/no pseudo tracks in both audio and video lists → false
    - hasRealTrack: default/empty Tracks() → false
    - parseTrackCount('0') → 0; parseTrackCount('3') → 3; parseTrackCount(' 2 ') → 2 (trims whitespace)
    - parseTrackCount(null) → null; parseTrackCount('') → null; parseTrackCount('garbage') → null (degrade signal, never throws)
  </behavior>
  <action>
    Write the failing tests above first (mirror the structure/style of test/features/monitoring/helpers/stream_candidates_test.dart — plain group/test, no mocks), then implement lib/features/monitoring/helpers/stream_liveness.dart:

    1. `bool hasRealTrack(Tracks tracks)` — returns true when any entry in tracks.audio or tracks.video has an id that is not 'auto' and not 'no'. media_kit always prepends the AudioTrack.auto()/AudioTrack.no() and VideoTrack.auto()/VideoTrack.no() pseudo-tracks, so "real track present" = any entry with id outside {'auto', 'no'}. A real VIDEO track counts as alive so mic-disabled cameras keep working. Ignore tracks.subtitle. Defensive by contract: never throws (wrap the body in try/catch returning false on unexpected failure, matching the orderedStreamCandidates convention).
    2. `int? parseTrackCount(String? raw)` — `int.tryParse(raw?.trim() ?? '')` semantics: null input, empty, or unparseable string → null. Null is the "could not determine" signal the caller treats as degrade-to-assume-alive. Never throws.

    Import 'package:media_kit/media_kit.dart' for the Tracks/AudioTrack/VideoTrack types — these are plain Dart models, constructible in unit tests without native libmpv, so the test file needs no mocks or platform setup. Document both functions with dartdoc explaining their role in stream-liveness confirmation (positive-evidence check + mpv property fallback parse).
  </action>
  <verify>
    <automated>flutter test test/features/monitoring/helpers/stream_liveness_test.dart</automated>
  </verify>
  <done>stream_liveness.dart exists with hasRealTrack and parseTrackCount; tests cover real-audio-alive, video-only-alive (mic-disabled), pseudo-tracks-only-not-alive, empty-not-alive, and numeric/garbage/null parseTrackCount cases; all pass.</done>
</task>

<task type="auto">
  <name>Task 2: Rework _confirmStreamAlive — positive evidence + two-stage grace + track-list/count fallback</name>
  <files>lib/features/monitoring/providers/audio_player_provider.dart</files>
  <action>
    Rework `_confirmStreamAlive` (currently ~line 421) in lib/features/monitoring/providers/audio_player_provider.dart so declaring a candidate alive requires positive evidence, keeping the existing shape (subs list, `String? failure` accumulated inside try, throw after finally) so plumbing failures still degrade to assume-alive:

    1. Import lib/features/monitoring/helpers/stream_liveness.dart.
    2. Add a new const next to `_openConfirmGrace`: `static const _openConfirmExtendedGrace = Duration(seconds: 6);` with a dartdoc explaining it is the second-stage wait for slow VPN links before disqualifying a silent candidate. Update `_openConfirmGrace`'s dartdoc: timeout no longer implies alive; it triggers the track-list check + extended window.
    3. Alive signals (completer completes with null):
       - existing audioParams listener with sampleRate > 0 — keep as-is;
       - NEW: subscribe `player.stream.tracks` and complete(null) when `hasRealTrack(tracks)` — a real audio OR video track proves the RTSP session was established (video-only keeps mic-disabled cameras working).
    4. Dead signal (completer completes with the error string): existing `player.stream.error` listener — keep as-is.
    5. Two-stage timeout flow replacing the current `onTimeout: () => null`:
       a. Await the completer with `_openConfirmGrace` timeout, using a sentinel (e.g. a private const `_confirmTimedOut = ' timeout'` or a dedicated helper returning an enum-like result) to distinguish timeout from a real completion — do NOT reuse null, which means alive.
       b. On first timeout: read `(player.platform as NativePlayer).getProperty('track-list/count')` wrapped in its own try/catch, and parse with `parseTrackCount`. mpv's track-list contains only real demuxer tracks (no auto/no pseudo entries), so 0 means no session. If the read throws or parses to null → assume alive (set no failure, log via appLog that the liveness fallback was inconclusive). If it parses to a value > 0 → alive. Only if it parses to exactly 0:
       c. Await the SAME completer again with `_openConfirmExtendedGrace` timeout (the listeners from step 3/4 are still attached; an audioParams/tracks event completes it alive, an error event completes it dead). On a second timeout, re-read and re-parse track-list/count with the same per-call try/catch: parses to 0 → set `failure = '$label candidate showed no signs of life (no tracks) after open'`; throws or parses to null or > 0 → assume alive.
    6. After the flow, if the completer produced an error string at any stage, keep the existing `failure = '$label candidate errored right after open: <error>'` message shape (adjust so both failure kinds funnel into the single `if (failure != null) throw StateError(failure)` at the end — the existing string interpolation moves into failure assembly).
    7. Keep the outer try/catch that logs 'liveness check error (assuming alive)' and clears failure for any unexpected plumbing exception, and keep the finally block cancelling all subscriptions. The deliberate no-signs-of-life failure must be set as the `failure` string (not thrown inside the try) so the defensive catch cannot swallow real code paths while the intended disqualification still throws after the finally.
    8. Update the `_confirmStreamAlive` dartdoc: alive now requires positive evidence (audioParams with sampleRate > 0, or a real track via hasRealTrack, or track-list/count > 0); silence through both grace windows with a zero track count disqualifies the candidate so `_openFirstCandidate` proceeds to the next (remote/ts.net) candidate — this is the fix for the Tailscale exit-node blackhole where dropped SYNs produce no error event; plumbing failures still degrade to assume-alive.
    9. Do not change `_openFirstCandidate`, `_connectCamera`, `_performReconnectOpen`, or the supervisor/watchdog wiring — the per-candidate catch in `_openFirstCandidate` already turns the new throw into "try next candidate", which covers initial connect, reconnect, and quality switch alike. Worst case a dead candidate now costs 4s + 6s = 10s before the next candidate is tried, which stays within the existing per-candidate timeout scale (12s open / 15s reconnect).

    Commit as `fix(monitoring): require positive liveness evidence before declaring stream candidate alive` (Conventional Commits — release-please parses this).
  </action>
  <verify>
    <automated>flutter analyze && flutter test test/features/monitoring/</automated>
  </verify>
  <done>_confirmStreamAlive treats grace-window silence as dead only when a final track-list/count check parses to 0 after both the 4s and the extended 6s window; real audio or video tracks, audioParams, track-list/count > 0, or any plumbing/parse failure all resolve to alive; error events still disqualify immediately; analyze and monitoring tests pass.</done>
</task>

</tasks>

<verification>
- `flutter analyze` clean (use /root/flutter/bin/flutter if flutter is not on PATH)
- `flutter test test/features/monitoring/` passes, including the new stream_liveness tests
- `_openConfirmExtendedGrace` const exists and the no-signs-of-life StateError is thrown only after the extended window plus a zero track-list/count re-check
- The throw funnels through the existing `failure` variable so the defensive outer catch still converts plumbing exceptions to assume-alive
- Commit message follows Conventional Commits (`fix(monitoring): ...`)
</verification>

<success_criteria>
- Over Tailscale with the UDM Pro as exit node, the blackholed `local` candidate is disqualified within ~10s and the `remote` (ts.net) candidate is tried — monitoring produces audio instead of a silent zombie loop
- Local-network and plain-Tailscale behavior unchanged: candidates with real tracks/audioParams confirm alive at the first signal, error events disqualify fast
- Mic-disabled cameras (video track only) still confirm alive
- No exception from the liveness check can kill a running audio stream or skip the remaining candidates
- No pubspec changes
</success_criteria>

<output>
Create `.planning/quick/260723-skr-fix-false-alive-stream-candidate-confirm/260723-skr-SUMMARY.md` when done
</output>
