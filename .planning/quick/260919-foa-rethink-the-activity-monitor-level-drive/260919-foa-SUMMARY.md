---
phase: quick-260919-foa
plan: 01
subsystem: monitoring
tags: [audio-level, noise-floor, waveform, mpv, bitrate, riverpod, custom-paint, settings]
requires:
  - phase: quick-260723-sph
    provides: bitrate-as-loudness-proxy decision, levelHistory in CameraAudioState, _WaveformChart slot
  - phase: 04-reliability-overnight-monitoring
    provides: ZombieWatchdog / DriftWatchdog fed from the same poll loop
provides:
  - PcmLevelTap: second silent mpv Player per camera, ao=pcm into a named pipe — real loudness without filters
  - PcmFifo: libc-FFI non-blocking FIFO reader; PcmLevelMeter: s16 PCM → short-term RMS dBFS
  - AudioLevelTracker: per-camera, noise-floor-relative, smoothed 0..1 level from any dB signal (pure Dart)
  - Card border/halo driven directly by that level (smoothstep above the trigger)
  - 60 s waveform of the same level series with threshold guides and 10 s ticks
  - levelThreshold setting (default 0.25, new JSON key), slider 0.05..0.6
  - 250 ms poll cadence with re-entrancy guard; metadata reads every 2 s
affects: [monitoring, settings]
tech-stack:
  added: []
  patterns:
    - Stateful pure-Dart signal processor (dart:math + dart:collection only) owned by the provider, one per camera, lifecycle mirroring an existing per-camera map
    - Two-Path fill for sub-pixel bar charts (no anti-aliasing seams)
key-files:
  created:
    - lib/features/monitoring/services/pcm_fifo.dart
    - lib/features/monitoring/services/pcm_level_tap.dart
    - lib/features/monitoring/helpers/pcm_level.dart
    - test/features/monitoring/helpers/pcm_level_test.dart
    - test/features/monitoring/services/pcm_fifo_test.dart
  modified:
    - pubspec.yaml
    - lib/features/monitoring/helpers/audio_level_meter.dart
    - lib/features/monitoring/models/player_state.dart
    - lib/features/monitoring/providers/audio_player_provider.dart
    - lib/features/monitoring/widgets/camera_audio_card.dart
    - lib/features/monitoring/screens/monitoring_screen.dart
    - lib/core/providers/settings_provider.dart
    - lib/features/settings/screens/settings_screen.dart
    - test/features/monitoring/helpers/audio_level_meter_test.dart
    - test/features/monitoring/widgets/camera_audio_card_test.dart
    - test/core/providers/settings_provider_test.dart
    - test/core/theme/light_theme_smoke_test.dart
    - README.md
    - CLAUDE.md
decisions:
  - "Loudness comes from decoded PCM via a SECOND silent mpv Player per camera (ao=pcm → FIFO); the Android FFmpeg is --disable-filters (read from libmpv.so), so no analysis filter can ever exist, and encoded AAC bitrate is near-constant (hardware feedback). The main player is never touched — a tap failure costs the meter, not the stream"
  - "FIFO over file (16 KB/s forever), libc FFI over dart:io (mkfifo does not exist there and a blocking open would pin an IO thread); teardown is writer-then-reader to avoid SIGPIPE, and SIGPIPE is additionally ignored"
  - "Level is RELATIVE to the room on any signal: floor = min of per-second minima of a 2 s-smoothed dB signal over a rolling 5 min window, ceiling likewise from maxima; span clamped to 30..50 dB for PCM (speech ≈ +25 dB stays below full scale), 6..24 dB for the bitrate fallback"
  - "One number drives everything: CameraAudioState.audioLevel is the tracker's display level, levelHistory is that same value appended per tick — border, level bar and waveform can never disagree. audioActivity and recentVariation are gone"
  - "Envelope is VU-style: instant attack, 0.8 s exponential release, so the border fades rather than blinks and a steady cry stays lit"
  - "Poll cadence 250 ms; only audio-pts, audio-bitrate and demuxer-cache-duration every tick, the nine metadata properties every 8th tick; watchdogs receive the real interval so thresholds are unchanged"
  - "Threshold setting renamed levelThreshold and persisted under a NEW key: the old activityThreshold default (0.05) meant 'peak-to-trough swing' and would light the border on every jitter under the new semantics"
  - "Border width stays 2 px (Container pads by border width, so a level-driven width would shift layout every tick); alpha + halo carry the level"
  - "Waveform colours: ambient in onSurface@0.35, above-threshold in the live colour, so green literally means 'the card was glowing'"
metrics:
  duration: ~45min
  tasks: 3
  files: 13
  completed: 2026-09-19
status: complete
---

# Quick Task 260919-foa: Level-driven activity monitor and 60 s waveform Summary

**The card now glows in proportion to how loud the room actually is — measured from decoded audio, not encoded bitrate — and the waveform is a 60 s record of that same signal.**

## What Was Built

1. **`AudioLevelTracker`** (`audio_level_meter.dart`, pure Dart): `bitrateToDb` → 0.4 s EMA → normalise against a rolling noise floor/ceiling (per-second min/max of a slower 2 s EMA, 5 min window, 2 s warm-up skipped) → span clamped 6..24 dB → instant-attack / 0.8 s-release envelope. `!flowing` decays to 0 without touching the floor; flowing-with-no-bitrate holds. 22 unit tests including relativity (same bitrate is loud in a quiet room, silent in a noisy one), span learning, monotonic release, outlier rejection and NaN safety.

2. **Provider**: one tracker per camera in `_levelTrackers` (lifecycle mirrors `_lastAudioPts`: cleared on stop/dispose, removed on camera removal and successful reconnect). Poll at `kLevelPollInterval` (250 ms) behind a re-entrancy guard; fast path reads three properties, metadata every 8th tick. `audioActivity` removed from `CameraAudioState`.

3. **Card**: `_levelIntensity` = smoothstep of `(level − threshold)/(1 − threshold)` → border alpha and halo blur/spread. `_WaveformChart` takes the threshold, paints 240 slots as two unioned Paths (ambient / above-threshold), mirrored guide lines, 10 s ticks and a "60s" caption; the painter's `paint` is wrapped so a bad frame degrades to a blank chart.

4. **Settings**: `levelThreshold` (default 0.25, slider 0.05..0.6 with 11 divisions and a % label, copy in terms of "above the room's quiet level"); `fromJson` ignores the legacy `activityThreshold` key.

5. **PCM tap (after hardware feedback that bitrate barely moves)**: `PcmFifo` (libc FFI, non-blocking), `PcmLevelMeter` (loudest 50 ms RMS window per tick, dBFS), `PcmLevelTap` (second silent `Player` with `ao=pcm`/`ao-pcm-file`/`s16`/mono/8 kHz, safe teardown). Provider starts a tap per live camera, samples it every tick, drops and retries it on failure/stall/URL change (20 s cooldown), and swaps the tracker between `.pcm()` and `.bitrate()` presets as the source changes. `levelSource`/`levelDb` on the state feed a "Meter" row in the details panel.

## Verification

- `flutter analyze --fatal-infos` — No issues found.
- `flutter test` — 498 tests passing (25 tracker tests, 9 PCM meter tests, 4 FIFO tests through real libc on the Linux host, 2 new widget tests).
- End-to-end with a real `mpv 0.37` binary (installed in the session): the exact tap flags produced exactly 144 000 bytes for a 9 s WAV (= 8 kHz × 2 B, headerless mono), read through `PcmFifo`; the meter reported −6 dBFS for the −6 dB-peak passage and −50 dBFS for the −50 dB tail (44 dB swing; a fixed ~3 dB offset from mpv's downmix is irrelevant to a floor-relative meter).
- Inspected `default-arm64-v8a.jar` (libmpv-android-video-build v1.1.7): FFmpeg configure has `--disable-filters` with only `overlay`/`equalizer` re-enabled; `ao_pcm` ("RAW PCM/WAVE file writer") and `ao-pcm`/`waveheader` option strings present.
- Rendered the card to PNG in a scratch widget test with a synthetic minute (quiet jitter, 10 s cry, short fuss): grey ambient ribbon, full-height green burst with a visible release tail, half-height fuss, halo present only on the loud card; checked in dark and light themes.
- grep gates: `audioActivity`, `recentVariation`, `bitrateToLevel`, `activityThreshold` → 0 matches in `lib/` and `test/` (the last remains only in the settings migration comment/test).

## Deviations from Plan

- The calibration ring is fed by a separate slower (2 s) smoothing rather than the display smoothing: with the 0.4 s EMA a single tiny packet dragged the floor ~9 dB down for the whole window (caught by the outlier unit test). Ring entries store both the stride minimum (floor) and maximum (ceiling).
- Added a re-entrancy guard to the poll loop (not in the plan) after re-reading the diff: the timer does not await the previous tick, and at 4 Hz an overrun would have raced the history append.

## Known Limitations

- Not verified against real camera hardware in this session: the tap doubles RTSP sessions to the console (one per camera), which is expected to be fine (NVRs serve several viewers) but has not been confirmed on a real Protect console. If the console refuses the extra session, the tap fails, retries every 20 s, and the meter falls back to bitrate.
- The span/window/trigger constants (30..50 dB, 5 min, 0.25) are engineering estimates to be tuned on a real nursery.
- Windows has no FIFOs: the meter stays on the bitrate fallback there.
- A sound sustained for longer than the 5 min window becomes the new floor by design.
