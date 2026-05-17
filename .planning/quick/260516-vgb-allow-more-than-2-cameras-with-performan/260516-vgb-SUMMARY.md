---
phase: quick-260516-vgb
plan: 01
subsystem: cameras-monitoring-ui
tags: [ui, state, riverpod, material3, quick-task]
requirements:
  - QUICK-260516-VGB
dependency_graph:
  requires: []
  provides:
    - CameraState.hasPerformanceRisk
    - "_LiveToolbar.cameraCount"
  affects:
    - lib/features/cameras/providers/camera_state.dart
    - lib/features/cameras/providers/camera_provider.dart
    - lib/features/monitoring/screens/monitoring_screen.dart
tech_stack:
  added: []
  patterns:
    - "Tonal Material 3 advisory: tertiaryContainer surface + onTertiaryContainer foreground for non-blocking warnings (no new theme role)."
key_files:
  created: []
  modified:
    - lib/features/cameras/providers/camera_state.dart
    - lib/features/cameras/providers/camera_provider.dart
    - lib/features/monitoring/screens/monitoring_screen.dart
decisions:
  - "[Quick 260516-vgb] 2-camera cap is advisory, not technical. Replace gate with hasPerformanceRisk-driven banner (picker) + cameras.length>2 chip (live toolbar). Same copy in both surfaces."
  - "[Quick 260516-vgb] No new warning theme role added. Reuse Material 3 tertiaryContainer; project does not define a dedicated warning role and a one-off tonal surface is the lowest-risk choice."
metrics:
  duration_seconds: 124
  duration_human: "~2 min"
  tasks_completed: 1
  files_modified: 3
  completed: "2026-05-17T09:17:01Z"
commits:
  - "2963cba: feat(quick-260516-vgb-01): allow more than 2 cameras with performance warning"
---

# Quick Task 260516-vgb: Allow More Than 2 Cameras with Performance Warning — Summary

Replaced the hard 2-camera cap in `CameraState` / `toggleCamera` / `_IdleCameraPicker` with an advisory warning surface, so users who want 3+ rooms overnight are allowed through with a non-blocking heads-up; no playback paths touched.

## What Changed

### `lib/features/cameras/providers/camera_state.dart`
- `canStartMonitoring` is now `selectedIds.isNotEmpty` (cap dropped).
- New getter `hasPerformanceRisk => selectedIds.length > 2;` drives the picker-side banner.

### `lib/features/cameras/providers/camera_provider.dart`
- `toggleCamera` always adds when the camera isn't already selected — the `else if (newIds.length < 2)` / `else { return; }` silent-rejection branch is gone. Log message format unchanged.

### `lib/features/monitoring/screens/monitoring_screen.dart`
- Idle picker doc comment: "Idle state: pick cameras to monitor + Start Monitoring." (was "up to 2 cameras").
- Idle picker header copy: **"Choose cameras to monitor — 2 recommended"** (was "Choose 1 or 2 cameras to monitor").
- Removed `final atLimit = state.selectedIds.length >= 2;` and the `muted`/`Opacity(opacity: muted ? 0.5 : 1.0, ...)` wrapper around `CheckboxListTile`. Non-selected items are always tappable.
- New warning banner between the `Expanded(ListView)` and the bottom `SafeArea` Start button: tonal `Container` (`tertiaryContainer` background, `onTertiaryContainer` foreground) with `Icons.warning_amber_outlined` + `Spacing.lg` horizontal / `Spacing.sm` vertical padding. Renders only when `state.hasPerformanceRisk`.
- `_LiveToolbar` extended with `final int cameraCount;` (required). When `cameraCount > 2`, a compact `Chip` warning is rendered as the first child of the toolbar Row (before the title `Expanded`). Same copy as the picker banner.
- `_LiveMonitoringView.build` passes `cameraCount: state.cameras.length` to `_LiveToolbar`.

Both surfaces use the exact copy:

> More than 2 cameras may degrade performance and battery life.

## Verification

- `flutter analyze lib/features/cameras/providers/camera_state.dart lib/features/cameras/providers/camera_provider.dart lib/features/monitoring/screens/monitoring_screen.dart` → **No issues found!** (3.4s)
- `grep -nE '(<= ?2|< ?2|>= ?2)'` across the three files → **no matches** (cap literals fully removed; the only `> 2` literal is the intentional `hasPerformanceRisk` getter and the toolbar chip predicate).
- `grep -n 'More than 2 cameras may degrade performance and battery life'` → matches at line 359 (`_LiveToolbar` chip) and line 518 (idle picker banner) of `monitoring_screen.dart`.
- `grep -n 'hasPerformanceRisk'` → defined at `camera_state.dart:11`, consumed at `monitoring_screen.dart:501`.

Done criteria from the plan, all satisfied:
- [x] `canStartMonitoring` no longer enforces `length <= 2`.
- [x] `hasPerformanceRisk` getter on `CameraState` returns `length > 2`.
- [x] `toggleCamera` no longer rejects additions past 2.
- [x] Idle picker: no `atLimit` / `Opacity` muting; header copy updated; warning banner renders only when selection > 2.
- [x] Live monitoring toolbar: warning chip renders only when active camera count > 2.
- [x] `flutter analyze` clean for the three files.
- [x] Audio/Player code paths (audio_player_provider, audio_handler, etc.) untouched. `git show 2963cba --stat` lists exactly three files, none of them under `lib/features/monitoring/providers/audio_*` or `lib/features/monitoring/services/audio_handler.dart`.

## Manual Smoke Test (developer)

To exercise on device/desktop:

1. Launch app → Monitor tab idle picker.
2. Select 1 camera → no banner, Start enabled.
3. Select 2 cameras → no banner, Start enabled.
4. Select 3rd camera → checkbox accepts the tap; tonal banner appears under the list; Start still enabled.
5. Deselect back to 2 → banner disappears.
6. Start monitoring with 3 cameras → toolbar shows compact `Chip` warning; all three `CameraAudioCard`s render.
7. Stop → picker returns; selection persists with banner still visible.

## Deviations from Plan

None — plan executed exactly as written. Edits matched the plan's interface specs (state.hasPerformanceRisk getter, toggleCamera unconditional-add, picker copy update, banner placement under the list, `_LiveToolbar.cameraCount` plumbing, chip-as-first-Row-child).

## Decisions Made

- **Reused Material 3 `tertiaryContainer` for the advisory surface.** The project's theme has no dedicated `warning` role, and introducing one for a quick advisory would have exceeded the scope ("No new dependencies; use existing Material 3 components"). Tertiary tonal is the Material 3-recommended choice for non-critical advisory surfaces.
- **Identical copy across picker banner and live chip.** The plan specified the same copy in both surfaces and matching color tokens; kept it verbatim so the message is recognisable across states.
- **`Chip` over hand-rolled container in the toolbar.** The plan explicitly preferred `Chip` with `visualDensity: VisualDensity.compact` for the toolbar warning; kept that to leverage Material 3 chip semantics (accessible role, dense layout) without extra layout code.

## Known Stubs

None. The warning text is literal copy from the plan; the predicate sources (`state.hasPerformanceRisk`, `state.cameras.length`) are live Riverpod state.

## Files

- Plan: `/Users/fvoska/projects/personal/rtsp-audio-mixer/.planning/quick/260516-vgb-allow-more-than-2-cameras-with-performan/260516-vgb-PLAN.md`
- Modified:
  - `/Users/fvoska/projects/personal/rtsp-audio-mixer/lib/features/cameras/providers/camera_state.dart`
  - `/Users/fvoska/projects/personal/rtsp-audio-mixer/lib/features/cameras/providers/camera_provider.dart`
  - `/Users/fvoska/projects/personal/rtsp-audio-mixer/lib/features/monitoring/screens/monitoring_screen.dart`

## Self-Check: PASSED

- FOUND: `lib/features/cameras/providers/camera_state.dart`
- FOUND: `lib/features/cameras/providers/camera_provider.dart`
- FOUND: `lib/features/monitoring/screens/monitoring_screen.dart`
- FOUND: `.planning/quick/260516-vgb-allow-more-than-2-cameras-with-performan/260516-vgb-SUMMARY.md`
- FOUND: commit `2963cba` in `git log`
- AUDIO_UNTOUCHED: commit `2963cba --stat` contains no `audio_player_provider` / `audio_handler` / `camera_audio_card` paths
