---
phase: 02-rtsp-audio-streaming
plan: 01
subsystem: monitoring
tags: [media_kit, rtsp, audio, models, helpers]
dependency_graph:
  requires: []
  provides: [media_kit-deps, rtsp-url-helpers, pan-filter-helper, player-state-model, mediakit-init]
  affects: [02-02-PLAN]
tech_stack:
  added: [media_kit, media_kit_libs_audio, media_kit_native_event_loop, media_kit_libs_macos_audio, media_kit_libs_android_audio]
  patterns: [immutable-value-objects, pure-helper-functions, tdd-red-green]
key_files:
  created:
    - lib/features/monitoring/helpers/rtsp_url.dart
    - lib/features/monitoring/helpers/pan_filter.dart
    - lib/features/monitoring/models/player_state.dart
    - test/features/monitoring/rtsp_url_test.dart
    - test/features/monitoring/pan_filter_test.dart
    - test/features/monitoring/player_state_test.dart
  modified:
    - pubspec.yaml
    - lib/main.dart
decisions:
  - Used audio-only media_kit_libs variants to minimize binary size and CPU usage
  - Pan filter uses mono-to-stereo lavfi format compatible with mpv af property
metrics:
  duration: 5min
  completed: "2026-04-03T19:26:50Z"
  tasks_completed: 2
  tasks_total: 2
  tests_added: 20
  files_changed: 8
---

# Phase 02 Plan 01: Media Kit Foundation Summary

media_kit audio-only dependencies installed, RTSP URL construction and stereo pan filter helpers implemented with TDD, per-camera audio state model ready for provider consumption

## What Was Done

### Task 1: media_kit Dependencies and Helper Functions (TDD)

Added 5 media_kit packages to pubspec.yaml (audio-only variants to avoid video decoding overhead). Created two pure helper functions following TDD red-green flow:

- **rtspUrl / rtspsUrl** -- construct Unifi Protect RTSP URLs from NVR host and camera ID, handling trailing slashes and correct ports (7447 unencrypted, 7441 encrypted with SRTP)
- **buildPanFilter** -- generates mpv lavfi pan filter string for stereo panning from mono camera input, with value clamping at -1.0 to 1.0 range

Commit: `32eb18f`

### Task 2: Player State Model and MediaKit Initialization

Created immutable value objects for per-camera audio state management:

- **CameraConnectionStatus** enum (idle, connecting, playing, error)
- **CameraAudioState** -- tracks volume, pan, mute state, pre-mute volume for restore, connection status, and error messages per camera. Provides `effectiveVolume` (0 when muted) and copyWith for immutable updates.
- **MonitoringState** -- wraps list of CameraAudioState with `allLive`, `anyError`, and `copyWithCamera` helpers

Updated main.dart to call `WidgetsFlutterBinding.ensureInitialized()` and `MediaKit.ensureInitialized()` before app startup.

Commit: `0de33dd`

## Test Coverage

- 4 RTSP URL tests (construction, trailing slash handling for both rtsp/rtsps)
- 6 pan filter tests (center, full left, full right, partial pan, clamping above/below)
- 10 player state tests (defaults, effectiveVolume muted/unmuted, copyWith, isLive, isError, allLive, anyError, copyWithCamera)
- **Total: 20 new tests, 47 tests in full suite -- all passing**

## Deviations from Plan

None -- plan executed exactly as written.

## Known Stubs

None -- all functions are fully implemented with real logic.
