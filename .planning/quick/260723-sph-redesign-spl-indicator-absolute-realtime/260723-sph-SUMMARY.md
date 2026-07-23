---
phase: quick-260723-sph
plan: 01
subsystem: monitoring
tags: [audio-level, pseudo-spl, waveform, mpv, bitrate, riverpod, custom-paint]
requires:
  - phase: 02-streaming
    provides: media_kit players, _pollAudioLevels loop, audio-pts flow detection
  - phase: 04-reliability-overnight-monitoring
    provides: ZombieWatchdog bitrate/pts feeds, ReconnectSupervisor status flow
provides:
  - Pure-Dart audio_level_meter helper (bitrateToLevel, appendLevel, recentVariation + shared constants)
  - CameraAudioState.levelHistory rolling pseudo-SPL buffer (capacity 20 / 10 s)
  - Absolute log-mapped bitrate→level bar (floor 2 kbps → 0.0, ceiling 96 kbps → 1.0)
  - Variation-driven (peak-to-trough ~5 s) card-border highlight
  - _WaveformChart Audacity-style mirrored 10 s waveform on live camera cards
affects: [monitoring, settings]
tech-stack:
  added: []
  patterns:
    - Pure-math helper files with only dart:math imports for unit-testability without native libs
    - Identity-based shouldRepaint on per-tick new list instances for cheap CustomPainter invalidation
key-files:
  created:
    - lib/features/monitoring/helpers/audio_level_meter.dart
    - test/features/monitoring/helpers/audio_level_meter_test.dart
  modified:
    - lib/features/monitoring/models/player_state.dart
    - lib/features/monitoring/providers/audio_player_provider.dart
    - lib/features/monitoring/widgets/camera_audio_card.dart
    - lib/features/settings/screens/settings_screen.dart
    - test/features/monitoring/widgets/camera_audio_card_test.dart
decisions:
  - "Loudness proxy is mpv audio-bitrate (VBR AAC encoded bitrate correlates with signal energy) — the only signal available without lavfi filters, which kill the stream on this FFmpeg build"
  - "Fixed log mapping ln-scale 2000..96000 bps — deterministic, identical bounds on every camera, no adaptive baseline anywhere"
  - "Activity = peak-to-trough (max−min) over last 10 samples (~5 s), no peak-hold decay — the sliding window IS the decay"
  - "levelHistory stored as List.unmodifiable so no consumer can mutate state under the painter's identity-based shouldRepaint"
  - "Amber low-level bar branch deleted — low absolute level is a normal quiet nursery, not a warning; pinned by widget test"
metrics:
  duration: 8min
  tasks: 3
  files: 7
  completed: 2026-07-23
status: complete
---

# Phase quick-260723-sph Plan 01: Redesign SPL Indicator (Absolute + Realtime) Summary

**Absolute pseudo-SPL level bar via fixed log mapping of mpv audio-bitrate, variation-driven (peak-to-trough) border highlight, and a 10 s Audacity-style mirrored waveform per live camera card — replacing the pts-delta flow proxy and EMA baseline.**

## What Was Built

1. **`audio_level_meter.dart`** (pure Dart, single `dart:math` import): `bitrateToLevel` (log mapping 2 kbps→0.0 / 96 kbps→1.0, guards null/≤0/NaN/∞ → 0.0), `appendLevel` (capacity-capped rolling history returning a new unmodifiable list), `recentVariation` (peak-to-trough over the last 10 samples), plus shared constants `kBitrateFloorBps`, `kBitrateCeilingBps`, `kLevelHistoryCapacity` (20), `kVariationWindow` (10). 15 unit tests cover bounds, clamping, garbage input, monotonicity, geometric midpoint, capacity eviction, immutability, and window limiting.

2. **Model + poll loop**: `CameraAudioState.levelHistory` (default `const []`, explicit `const []` in copyWith clears — the reconnect path relies on this). In `_pollAudioLevels` the `audio-bitrate` read moved up next to the pts-flow computation (ZombieWatchdog `recordBitrateNonZero` feed moved with it, same try/catch shape); level is `0.0` when not flowing, `bitrateToLevel(bitrate)` when flowing with a valid bitrate, and carries the previous level when flowing but bitrate not yet published (~1 s after open — never flashes silent). EMA baseline + peak-hold decay replaced by `appendLevel` + `recentVariation`; `_baselineLevel` deleted at all six touch-points (grep gate: 0 matches). Live cameras now always emit a state update per tick (history sample makes state unequal anyway); notification text-diff guard unchanged. `_applyReconnectStatus` clears `levelHistory` and zeroes `audioActivity` in the same single copyWith that flips status to playing. Silence/zombie/drift watchdog semantics byte-for-byte unchanged; all new math stays inside the existing per-camera try/catch; zero new mpv property reads, zero setProperty calls, no lavfi.

3. **Card UI + settings copy**: `_AudioLevelIndicator` bar is red when suspiciously silent, otherwise green — amber `level > 0.1` branch deleted (would glow all night on a quiet nursery; decision pinned by widget test). New `_WaveformChart` — `RepaintBoundary(CustomPaint(key: ValueKey('waveform-chart'), height 40))` — mounts below the level bar inside `if (cs.isLive)`: 1 px center line (onSurface α0.15), mirrored bars (primary α0.8, min 1 px half-height so silence shows a tick), fixed 20-slot grid with samples right-aligned so the trail grows from the right edge, identity-based `shouldRepaint`. Border-highlight gate + alpha formula unchanged, comment updated to variation semantics. Settings `_activityLabel` reworded to describe sensitivity to changes in sound level (small swings vs large swings like crying); key/range/persistence untouched.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Dropped the dead `infoChanged` computation instead of keeping it**
- **Found during:** Task 2
- **Issue:** The plan said "Keep computing `infoChanged`/`newInfo` as-is" while also dropping the state-update gating — but with the gate gone, `infoChanged` has no consumer and trips the analyzer's `unused_local_variable` warning, violating the "analyze is clean" done-criterion.
- **Fix:** `newInfo` is kept and still flows into the copyWith; the `infoChanged` boolean (dead code) was removed with a comment explaining the always-emit rationale.
- **Files modified:** lib/features/monitoring/providers/audio_player_provider.dart
- **Commit:** 97d978d

## Verification

- `flutter analyze lib` — No issues found.
- `flutter test` — full suite green: 295 tests (15 new helper unit tests, 3 new widget tests, all pre-existing tests unchanged and passing).
- Grep gates: `_baselineLevel` in provider → 0 matches; `ValueKey('waveform-chart')` in card → 1 match; helper has exactly one import (`dart:math`).
- Manual hardware check (quiet room / talking / network kill) left to the developer as noted in the plan — optional.

## Known Stubs

None — all data paths are wired; no placeholders, skipped tests, or unrun verifies.

## Threat Flags

None — no new network surface, no new mpv property reads, no setProperty/lavfi calls (T-qsph-01/02/03 mitigations implemented as planned and unit-tested).

## Commits

| Task | Commit | Message |
|------|--------|---------|
| 1 | a5e03b9 | feat(monitoring): add pure bitrate-to-level meter helper with rolling history and variation |
| 2 | 97d978d | feat(monitoring): derive audio level from encoded bitrate with rolling history and variation-based activity |
| 3 | 90c8233 | feat(monitoring): waveform chart and variation-driven highlight on camera cards |

## Self-Check: PASSED

All created files present on disk; all three task commits found in git history; grep gates re-verified.
