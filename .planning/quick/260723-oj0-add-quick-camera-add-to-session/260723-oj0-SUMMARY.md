---
phase: 260723-oj0
plan: 01
subsystem: monitoring
status: complete
tags: [monitoring, audio, riverpod, ui, quick-add]
requires:
  - AudioPlayerNotifier.startMonitoring / removeCamera (existing single-camera lifecycle)
  - cameraNotifierProvider (loaded/trusted camera list + selection persistence)
provides:
  - AudioPlayerNotifier.addCameraToSession(cameraId, {videoPreview})
  - AudioPlayerNotifier._connectCamera (shared single-camera connect helper)
  - addableCameras(all, inSession) pure helper
  - Live-view "Add camera" affordance + modal picker
affects:
  - lib/features/monitoring/providers/audio_player_provider.dart
  - lib/features/monitoring/screens/monitoring_screen.dart
tech-stack:
  added: []
  patterns:
    - Single-source per-camera connect logic via _connectCamera (no duplicated open/candidate block)
    - Append-only live-mix mutation (no AsyncLoading / stopMonitoring on the add path)
    - Defensive try/catch around all non-critical add-path work (health, notification, persistence, mix restore)
key-files:
  created: []
  modified:
    - lib/features/monitoring/providers/audio_player_provider.dart
    - lib/features/monitoring/screens/monitoring_screen.dart
    - test/features/monitoring/audio_player_provider_test.dart
    - test/features/monitoring/screens/monitoring_screen_live_test.dart
decisions:
  - Extracted the startMonitoring per-camera loop body into _connectCamera so add + start share one open/candidate/restore code path (divergence there would be a reliability bug per CLAUDE.md).
  - addCameraToSession runs inside _runLifecycle and appends to MonitoringState.cameras via copyWith — it never sets AsyncLoading and never calls stopMonitoring, so running players are untouched (T-oj0-01).
  - Add control carries the tooltip "Add camera to session" in BOTH the compact (IconButton) and non-compact (Tooltip-wrapped TextButton.icon) branches so it is findable/consistent at any width.
metrics:
  duration: ~15min
  completed: 2026-07-23
  tasks: 2
  files: 4
---

# Phase 260723-oj0 Plan 01: Add Quick Camera Add-to-Session Summary

Symmetric inverse of the existing quick-remove: while a session is live the user
can pick a camera not currently in the mix from a modal picker and have its audio
start immediately, without interrupting any already-running stream.

## What was built

### Task 1 — `addCameraToSession` notifier method (commit `263fcfa`)
- Refactored the per-camera connect block out of `startMonitoring`'s
  `for (final camera in selectedCameras)` loop into a private
  `Future<CameraAudioState> _connectCamera(ProtectCamera camera, {required bool videoPreview})`.
  `startMonitoring` now calls `cameraStates.add(await _connectCamera(...))`; all of
  its outer responsibilities (AsyncLoading, beginSession, health clear/monitoringStarted,
  full-list saved-mix restore, notification, level polling, connectivity listener)
  stay exactly where they were — only the per-camera body moved.
- Added `addCameraToSession(String cameraId, {bool videoPreview = false})`:
  runs through `_runLifecycle`; guards (no-op + `appLog`) when there is no monitoring
  state, no live session (`_players.isEmpty`), the camera is already in the mix, or the
  id can't be resolved from `cameraNotifierProvider`. On success it connects via
  `_connectCamera`, restores the camera's saved volume/mute from `mix_state`, appends the
  new `CameraAudioState` with `state = AsyncData(current.copyWith(cameras: [...]))`
  (re-reading `state.value` fresh after the await), persists selection via `toggleCamera`
  (only when not already selected), and records a `streamStarted` health event
  (`detail: 'added to mix'`) + refreshes the foreground notification. It never sets
  `AsyncLoading` and never calls `stopMonitoring`.
- Added top-level pure helper `addableCameras(all, inSession)` returning the cameras whose
  id is not already a `cameraId` in the mix — used by the UI and unit-tested here.

### Task 2 — Add-camera affordance + picker in the live view (commit `1d664cc`)
- Added `_onAddCamera(String cameraId)` to `_MonitoringScreenState` (calls
  `addCameraToSession` with the camera's current video preference) and threaded
  `onAddCamera` through `_LiveMonitoringView`.
- Added an "Add camera" control to `_LiveToolbar` — an `Icons.add` IconButton in the
  compact branch and a `Tooltip`-wrapped `TextButton.icon` (label "Add camera") in the
  non-compact branch, both with tooltip "Add camera to session".
- Tapping opens a `showModalBottomSheet` (`_AddCameraSheet`) listing
  `addableCameras(cameraState.cameras, state.cameras)` as ListTiles (name + optional
  source badge on mixed sources + Unifi connection dot), tolerant of a null camera state.
  Empty list shows "All cameras are already in this session." Picking a row pops the sheet
  and calls `onAddCamera(cam.id)`.

## Deviations from Plan

None — plan executed as written. (Minor implementation note: the add-path records a single
`streamStarted` health event with `detail: 'added to mix'`, mirroring how `removeCamera`
records `monitoringStopped` with `detail: 'removed from mix'`.)

## Threat mitigations

- **T-oj0-01 (DoS / stream teardown, mitigate):** the add path only appends a new `Player`;
  it never calls `AsyncLoading`/`stopMonitoring` and never touches existing `_players`
  entries. All new failure paths (mix restore, selection persistence, health, notification,
  and `_connectCamera`'s own open failure) are try/caught + logged, so a failed add leaves
  its one camera in `error` (with supervisor/alert handoff) while the others keep playing.
- **T-oj0-02 (accept):** no new packages added.

## Verification

- `flutter test test/features/monitoring/audio_player_provider_test.dart` — 16 passed
  (incl. 4 new `addableCameras` cases).
- `flutter test test/features/monitoring/screens/monitoring_screen_live_test.dart` — 9 passed
  (incl. 2 new: add control renders; picker lists only cameras not in the session).
- `flutter test test/features/monitoring/` — 209 passed (no regressions).
- `flutter analyze lib/features/monitoring/` — No issues found.

## Known Stubs

None.

## Self-Check: PASSED
