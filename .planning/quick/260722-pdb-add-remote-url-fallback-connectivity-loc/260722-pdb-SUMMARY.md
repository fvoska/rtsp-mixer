---
phase: quick-260722-pdb
plan: 01
subsystem: connectivity
tags: [rtsp, tailscale, vpn, fallback, riverpod, media_kit, unifi-protect]

# Dependency graph
requires:
  - phase: quick-260720-mrc
    provides: manual RTSP cameras (ProtectCamera.manual, manual_cameras storage, AuthMode.manual)
  - phase: 04-reliability-overnight-monitoring
    provides: ReconnectSupervisor + _performReconnectOpen reconnect path
provides:
  - replaceUrlHost(url, newHost) host-swap helper (never throws)
  - StorageService remote_host save/load/delete
  - ProtectCamera.remoteUrl (nullable, serialized, clearable via copyWith sentinel)
  - AuthState.remoteHost + AuthNotifier local→remote verify fallback, updateLocalHost/updateRemoteHost
  - CameraNotifier local→remote refresh fallback with active-API-host propagation, updateManualCamera
  - CameraAudioState.remoteQualities + ordered [local, remote] candidate opens in startMonitoring, reconnect, switchQuality
  - Settings Connection section, add-camera Remote URL field, Help "Remote access (VPN / Tailscale)" section
affects: [connectivity, monitoring, settings, cameras, auth]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Ordered [local, remote] candidate list with per-candidate open timeout; error only when ALL candidates fail"
    - "Reachability-error gate (connectionRefused/timeout) decides when remote fallback is attempted; auth errors never trigger fallback"
    - "Remote failure never masks the local error — local attempt's error is surfaced when both fail"

key-files:
  created:
    - test/features/monitoring/helpers/rtsp_url_test.dart
    - test/features/cameras/models/camera_model_test.dart
  modified:
    - lib/features/monitoring/helpers/rtsp_url.dart
    - lib/core/storage/storage_service.dart
    - lib/features/cameras/models/protect_camera.dart
    - lib/features/auth/models/auth_state.dart
    - lib/features/auth/providers/auth_provider.dart
    - lib/features/cameras/providers/camera_provider.dart
    - lib/features/monitoring/models/player_state.dart
    - lib/features/monitoring/providers/audio_player_provider.dart
    - lib/features/settings/screens/settings_screen.dart
    - lib/features/monitoring/screens/monitoring_screen.dart
    - lib/features/help/screens/help_screen.dart
    - test/core/storage/storage_service_test.dart

key-decisions:
  - "updateManualCamera uses empty-string-clears semantics (null = unchanged, '' = clear) instead of a sentinel, keeping the plan's String? signature"
  - "Initial open and quality switch use a 12s per-candidate timeout; reconnect keeps the pre-existing 15s timeout"
  - "Login leads the camera refresh with whichever host answered verification, keeping the other as fallback, to avoid a second connect-timeout wait"

patterns-established:
  - "Candidate fallback: build ordered [local, remote] list, try each with timeout, catch+log per candidate, fail only when all fail"

requirements-completed: [QUICK-260722-PDB]

coverage:
  - id: D1
    description: "replaceUrlHost swaps only the host of a stream URL, tolerating scheme prefixes/trailing slashes on newHost, never throwing"
    verification:
      - kind: unit
        ref: "test/features/monitoring/helpers/rtsp_url_test.dart#replaceUrlHost"
        status: pass
    human_judgment: false
  - id: D2
    description: "StorageService remote_host save/load/delete round-trip"
    verification:
      - kind: unit
        ref: "test/core/storage/storage_service_test.dart#remote host"
        status: pass
    human_judgment: false
  - id: D3
    description: "ProtectCamera.remoteUrl survives JSON round-trip, legacy JSON deserializes null, copyWith can set/clear/preserve"
    verification:
      - kind: unit
        ref: "test/features/cameras/models/camera_model_test.dart#ProtectCamera remoteUrl"
        status: pass
    human_judgment: false
  - id: D4
    description: "Auth verify/login and camera refresh succeed via remote host when local is unreachable, failing only when both fail"
    verification: []
    human_judgment: true
    rationale: "Requires a real Unifi console reachable only over VPN/Tailscale; the reachability-error fallback path cannot be exercised meaningfully without live network conditions"
  - id: D5
    description: "startMonitoring, reconnect, and quality switch iterate [local, remote] candidates, re-preferring local each reconnect cycle"
    verification: []
    human_judgment: true
    rationale: "media_kit Player opens against real RTSP endpoints; candidate ordering and timeout behavior need a live stream + network-toggle test overnight scenario"
  - id: D6
    description: "Settings Connection section (console local/remote, per-manual-camera remote URLs with clear), add-camera Remote URL field, Help remote-access section"
    verification: []
    human_judgment: true
    rationale: "Visual/UX verification of dialogs, validation messages, and section visibility rules"

# Metrics
duration: 13min
completed: 2026-07-22
status: complete
---

# Quick Task 260722-pdb: Remote URL Fallback Connectivity Summary

**Local-preferred / remote-fallback (VPN/Tailscale) connectivity for the Unifi console and manual RTSP cameras across auth, camera refresh, stream open, reconnect, and quality switch — with Settings editing and Help documentation**

## Performance

- **Duration:** ~13 min
- **Started:** 2026-07-22T18:22:02Z
- **Completed:** 2026-07-22T18:34:49Z
- **Tasks:** 3
- **Files modified:** 14 (11 lib + 3 test)

## Accomplishments

- Console and manual cameras can each carry a remote (VPN/Tailscale) address; every connection path tries local first and falls back to remote on reachability errors (connectionRefused/timeout), failing only when both fail
- Playback candidate fallback: `CameraAudioState.remoteQualities` parallels `availableQualities`; initial open, supervisor reconnect, and quality switch iterate an ordered [local, remote] candidate list with per-candidate open timeouts (12s initial/switch, 15s reconnect); reconnect rebuilds candidates each cycle so the app recovers to the LAN stream when back home
- Settings gains a Connection section: console local address + remote URL edit dialogs (with Clear), and per-manual-camera remote URL tiles; the add-camera dialog gets an optional validated Remote URL field; Help documents Remote access (VPN / Tailscale) including the remote-first-setup-add-local-later flow
- 25 new/extended unit tests (replaceUrlHost, remoteUrl JSON round-trip/legacy/copyWith, remote_host storage); full suite 246/246 green, `flutter analyze` clean

## Task Commits

Each task was committed atomically:

1. **Task 1 (RED): failing tests for data layer** - `6716172` (test)
2. **Task 1 (GREEN): remote host storage, model field, API fallback** - `05293b0` (feat)
3. **Task 2: playback [local, remote] candidate fallback** - `ff99e5f` (feat)
4. **Task 3: Settings Connection section, add-camera remote field, Help docs** - `cb13172` (feat)

## Files Created/Modified

- `lib/features/monitoring/helpers/rtsp_url.dart` - `replaceUrlHost` host-swap helper (never throws; normalizes pasted scheme/trailing slash)
- `lib/core/storage/storage_service.dart` - `saveRemoteHost`/`loadRemoteHost`/`deleteRemoteHost` on the `remote_host` key
- `lib/features/cameras/models/protect_camera.dart` - nullable `remoteUrl` field: constructor + manual factory param, serialized, sentinel-based copyWith (set/preserve/clear)
- `lib/features/auth/models/auth_state.dart` - `remoteHost` on the authenticated state (null for manual/unauthenticated)
- `lib/features/auth/providers/auth_provider.dart` - `_verifyWithFallback` (local→remote on reachability errors, local error surfaced when both fail) used by login + background validation; `updateLocalHost`/`updateRemoteHost`; `normalizeHostInput`
- `lib/features/cameras/providers/camera_provider.dart` - `loadCameras`/`_refreshFromApi` accept a fallback host; the answering host becomes the active API host for `getRtspsUrls`; `addManualCamera(remoteUrl:)`; new `updateManualCamera`
- `lib/features/monitoring/models/player_state.dart` - `CameraAudioState.remoteQualities` preserved in copyWith
- `lib/features/monitoring/providers/audio_player_provider.dart` - `_candidatesFor`/`_openWithTimeout`/`_openFirstCandidate` helpers; startMonitoring builds remote candidates (Unifi: `replaceUrlHost` + `resolveStreamUrl`; manual: `remoteUrl` verbatim); reconnect + switchQuality use the same candidate loop; `activeStreamUrl` always reflects the winning candidate
- `lib/features/settings/screens/settings_screen.dart` - Connection section with edit dialogs and Clear actions
- `lib/features/monitoring/screens/monitoring_screen.dart` - optional Remote URL field in the add-camera dialog with `_validateOptionalRtspUrl`
- `lib/features/help/screens/help_screen.dart` - "Remote access (VPN / Tailscale)" `_HelpSection`
- `test/features/monitoring/helpers/rtsp_url_test.dart` - 10 replaceUrlHost tests (new)
- `test/features/cameras/models/camera_model_test.dart` - 7 remoteUrl tests (new)
- `test/core/storage/storage_service_test.dart` - remote_host round-trip group (extended)

## Decisions Made

- **`updateManualCamera` clear semantics:** kept the plan's `String?` signature by defining null = leave unchanged, empty string = clear (a sentinel would have changed the signature). Settings' Clear action passes `''`.
- **Candidate timeouts:** 12s for initial open and quality switch (plan's "~12s"), 15s preserved for reconnect to match the pre-existing supervisor contract.
- **Login camera refresh ordering:** whichever host answered verification is passed as the primary refresh host with the other as fallback, so the refresh doesn't sit through a second 10s connect timeout.
- **`switchQuality` guard unchanged in spirit:** still short-circuits when the local URL equals `activeStreamUrl`; selecting the current quality while on the remote candidate re-runs the loop and thus re-prefers local (a useful manual recovery action).

## Deviations from Plan

None - plan executed exactly as written. (Test files were created at the plan's paths `test/features/monitoring/helpers/` and `test/features/cameras/models/`, which sit alongside older suites at `test/features/monitoring/rtsp_url_test.dart` and `test/features/cameras/camera_model_test.dart`; both coexist without conflict.)

## Issues Encountered

- **Pre-existing flaky test (out of scope, not fixed):** `test/features/monitoring/reconnect/per_camera_cancel_test.dart` ("cancels the pending retryTimer for that camera only") failed once during Task 3 verification and again in 2 of 4 isolated re-runs on identical code — randomized backoff jitter vs. the test's fixed `elapse(2s)` window inside `fakeAsync`. None of this task's changed files are exercised by that suite and `reconnect_supervisor.dart` was untouched. Logged in `deferred-items.md`; final full-suite run is 246/246 green.

## Known Stubs

None — no placeholders, hardcoded empty data paths, or TODO/FIXME markers introduced. (Grep of all modified lib files: clean.)

## User Setup Required

None in-code — but using the feature requires the user's own VPN (Tailscale/WireGuard) making the camera network routable; setup steps are documented in the new Help section.

## Next Phase Readiness

- Remote fallback is fully wired end to end; UAT should exercise: login with local unreachable, overnight reconnect re-preferring local, and Settings address editing (including the remote-first setup flow)
- Deferred: flaky `per_camera_cancel_test.dart` jitter-window fix (see deferred-items.md)

## Self-Check: PASSED

All 14 modified/created source+test files and the SUMMARY exist on disk; all four task commits (`6716172`, `05293b0`, `ff99e5f`, `cb13172`) are present in git history. Working tree contains only the pre-existing `pubspec.lock` change (intentionally left uncommitted) and the `.planning/quick/...` docs artifacts (orchestrator commits those).

---
*Phase: quick-260722-pdb*
*Completed: 2026-07-22*
