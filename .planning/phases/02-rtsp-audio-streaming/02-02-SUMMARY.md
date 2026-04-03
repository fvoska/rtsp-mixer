---
phase: 02-rtsp-audio-streaming
plan: 02
subsystem: monitoring
tags: [media_kit, rtsp, audio, riverpod, flutter-ui, volume, pan, stereo]
dependency_graph:
  requires:
    - phase: 02-01
      provides: media_kit-deps, rtsp-url-helpers, pan-filter-helper, player-state-model, mediakit-init
  provides: [audio-player-provider, monitoring-screen, camera-audio-card, stop-monitoring-button]
  affects: [02-03-PLAN, phase-03, phase-04]
tech_stack:
  added: []
  patterns: [async-notifier-with-native-resources, consumer-stateful-widget, card-based-control-ui]
key_files:
  created:
    - lib/features/monitoring/providers/audio_player_provider.dart
    - lib/features/monitoring/widgets/camera_audio_card.dart
    - lib/features/monitoring/widgets/stop_monitoring_button.dart
    - test/features/monitoring/audio_player_provider_test.dart
  modified:
    - lib/features/monitoring/screens/monitoring_screen.dart
key_decisions:
  - "Used ConsumerStatefulWidget for MonitoringScreen to trigger startMonitoring in initState"
  - "Sliders disabled (null onChanged) when camera is not in playing state"
  - "LinearProgressIndicator replaces sliders during connecting state for clearer visual feedback"
patterns_established:
  - "AsyncNotifier with native resource cleanup: _players map + ref.onDispose for Player disposal"
  - "CameraAudioCard as reusable ConsumerWidget with cameraIndex for provider method routing"
requirements-completed: [STRM-01, STRM-02, STRM-03]
metrics:
  duration: 3min
  completed: "2026-04-03T19:42:26Z"
  tasks_completed: 2
  tasks_total: 3
  tests_added: 12
  files_changed: 5
---

# Phase 02 Plan 02: RTSP Audio Player & Monitoring UI Summary

**Riverpod AudioPlayerNotifier managing dual media_kit Players with per-camera volume/pan/mute controls, wired to monitoring screen with CameraAudioCard widgets**

## Performance

- **Duration:** 3 min
- **Started:** 2026-04-03T19:39:20Z
- **Completed:** 2026-04-03T19:42:26Z
- **Tasks:** 2 of 3 (Task 3 is human-verify checkpoint, pending)
- **Files modified:** 5

## Accomplishments
- AudioPlayerNotifier with startMonitoring/stopMonitoring lifecycle, vid=no for audio-only, low-latency RTSP profile
- Per-camera volume slider (0-100), pan slider (L/R stereo via lavfi filter), mute/unmute with volume restore
- MonitoringScreen auto-starts streaming on load, StopMonitoringButton cleans up and navigates back
- 12 pure state tests covering volume, pan, mute, and MonitoringState transitions

## Task Commits

Each task was committed atomically:

1. **Task 1: Create audio player Riverpod provider with Player lifecycle management** - `b3481b9` (feat)
2. **Task 2: Build monitoring screen UI with CameraAudioCard, volume/pan sliders, and stop button** - `cb535cc` (feat)
3. **Task 3: Verify live RTSP audio streaming with volume and pan controls** - pending: human verification

## Files Created/Modified
- `lib/features/monitoring/providers/audio_player_provider.dart` - AsyncNotifier managing two Player instances with volume/pan/mute control
- `lib/features/monitoring/widgets/camera_audio_card.dart` - Per-camera card with status dot, volume slider, pan slider, mute button
- `lib/features/monitoring/widgets/stop_monitoring_button.dart` - OutlinedButton that stops players and navigates to camera list
- `lib/features/monitoring/screens/monitoring_screen.dart` - Replaced placeholder with ConsumerStatefulWidget wiring provider to UI
- `test/features/monitoring/audio_player_provider_test.dart` - 12 pure state tests for volume, pan, mute logic

## Decisions Made
- Used ConsumerStatefulWidget for MonitoringScreen to trigger startMonitoring in initState via Future.microtask
- Sliders disabled (null onChanged) when camera is not in playing state, per UI-SPEC interaction contract
- LinearProgressIndicator replaces sliders during connecting state for clearer visual feedback
- Mic disabled warning set as errorMessage but stream still attempted (camera may stream audio despite setting)

## Deviations from Plan

None -- plan executed exactly as written.

## Known Stubs

None -- all provider methods and UI widgets are fully implemented with real logic.

## Issues Encountered
None

## User Setup Required
None -- no external service configuration required.

## Next Phase Readiness
- Task 3 (human-verify checkpoint) must be completed: user needs to verify live RTSP audio from real cameras
- After verification, Phase 2 is complete and ready for Phase 3 (Android foreground service)
- All automated tests pass (59 total in full suite)

## Self-Check: PASSED

- All 5 created/modified files exist on disk
- Both task commits (b3481b9, cb535cc) verified in git log
- Full test suite: 59 tests passing

---
*Phase: 02-rtsp-audio-streaming*
*Completed: 2026-04-03 (Tasks 1-2; Task 3 pending human verification)*
