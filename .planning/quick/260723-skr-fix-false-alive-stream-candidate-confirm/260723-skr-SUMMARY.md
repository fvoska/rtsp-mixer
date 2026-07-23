---
phase: quick-260723-skr
plan: 01
subsystem: monitoring
tags: [rtsp, liveness, tailscale, exit-node, stream-candidates, media_kit]
requires: []
provides:
  - hasRealTrack + parseTrackCount pure liveness helpers
  - positive-evidence _confirmStreamAlive with two-stage grace and track-list/count fallback
affects: [stream-candidate-selection, reconnect, quality-switch]
tech-stack:
  added: []
  patterns:
    - positive-evidence liveness confirmation (silence is no longer proof of life)
    - two-stage grace window with mpv property belt-and-braces re-check
key-files:
  created:
    - lib/features/monitoring/helpers/stream_liveness.dart
    - test/features/monitoring/helpers/stream_liveness_test.dart
  modified:
    - lib/features/monitoring/providers/audio_player_provider.dart
decisions:
  - "Alive requires positive evidence: audioParams sampleRate > 0, a real audio OR video track (hasRealTrack), or mpv track-list/count > 0 — grace-window silence alone no longer confirms a candidate"
  - "Real VIDEO track counts as alive so mic-disabled cameras (no audioParams ever) keep working"
  - "track-list/count == 0 after both the 4s grace and the 6s extended grace is the only silence path that disqualifies; null/unparseable/throwing reads degrade to assume-alive per CLAUDE.md defensive rule"
  - "Deliberate no-signs-of-life disqualification funnels through the existing failure string thrown after finally, so the defensive outer catch can never swallow it while plumbing exceptions still degrade to assume-alive"
metrics:
  duration: 8min
  completed: 2026-07-23
status: complete
---

# Quick Task 260723-skr: Fix False-Alive Stream Candidate Confirmation Summary

Stream candidates must now show positive evidence (audioParams, a real audio/video track, or nonzero mpv track-list) before being declared alive — fixing the Tailscale exit-node blackhole where a silently-hanging local candidate was falsely crowned and the working remote (ts.net) candidate was never tried.

## Tasks Completed

| Task | Name | Commits | Files |
| ---- | ---- | ------- | ----- |
| 1 | Pure liveness helpers with unit tests (TDD) | 01779bf (RED), 3ea4037 (GREEN) | lib/features/monitoring/helpers/stream_liveness.dart, test/features/monitoring/helpers/stream_liveness_test.dart |
| 2 | Rework _confirmStreamAlive — positive evidence + two-stage grace + track-list/count fallback | f882daa | lib/features/monitoring/providers/audio_player_provider.dart |

## What Was Built

**stream_liveness.dart (new helpers):**
- `hasRealTrack(Tracks)` — true when any entry in `tracks.audio` or `tracks.video` has an id outside `{'auto', 'no'}` (media_kit always prepends those pseudo-tracks). A real VIDEO track counts, so mic-disabled cameras confirm alive. Subtitles ignored. Never throws (returns false on unexpected failure).
- `parseTrackCount(String?)` — `int.tryParse(raw?.trim() ?? '')`; null/empty/garbage → null (the inconclusive → assume-alive signal). Never throws.

**_confirmStreamAlive rework (audio_player_provider.dart):**
- New alive signal: `player.stream.tracks` subscription completing on `hasRealTrack` (alongside the existing audioParams sampleRate > 0 listener). Error events still disqualify immediately.
- New consts: `_openConfirmExtendedGrace` (6s second-stage wait for slow VPN links) and `_confirmTimedOut` sentinel (timeout no longer reuses null, which means alive).
- Two-stage flow: 4s grace timeout → read `track-list/count` via `_readLivenessTrackCount` (per-call try/catch). Parses null or > 0 → assume alive; exactly 0 → wait the same completer another 6s (listeners still attached) → re-read. Only 0-again sets `failure = '<label> candidate showed no signs of life (no tracks) after open'`.
- Both failure kinds (error event, no-signs-of-life) funnel into the single `if (failure != null) throw StateError(failure)` after the finally, so the defensive outer catch (`liveness check error (assuming alive)`) still converts plumbing exceptions to assume-alive while the intended disqualification throws.
- No changes to `_openFirstCandidate`, `_connectCamera`, `_performReconnectOpen`, or supervisor/watchdog wiring — the existing per-candidate catch turns the new throw into "try next candidate" for initial connect, reconnect, and quality switch alike. Worst case a dead candidate now costs 4s + 6s = 10s before the next candidate is tried.

## Verification

- `flutter analyze` — No issues found
- `flutter test test/features/monitoring/` — 222 tests passed (13 new stream_liveness tests)
- TDD gate: RED commit 01779bf (tests failed to compile against missing helper) → GREEN commit 3ea4037 (all 13 pass)
- No pubspec changes; no file deletions; working tree clean

## Deviations from Plan

None - plan executed exactly as written. (Two extra hardening tests beyond the listed behaviors: subtitle-tracks-ignored and hasRealTrack-never-throws.)

## Known Stubs

None.

## Self-Check: PASSED

- lib/features/monitoring/helpers/stream_liveness.dart — FOUND
- test/features/monitoring/helpers/stream_liveness_test.dart — FOUND
- lib/features/monitoring/providers/audio_player_provider.dart — FOUND
- Commits 01779bf, 3ea4037, f882daa — FOUND in git log
