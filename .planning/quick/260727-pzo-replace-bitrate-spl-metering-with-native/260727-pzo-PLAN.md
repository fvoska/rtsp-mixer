---
id: 260727-pzo
type: quick
description: Replace bitrate SPL metering with native Android PCM level analyzer sidecar and add branch-build CI workflow
created: 2026-07-27
---

# Quick Task 260727-pzo: Native PCM level metering sidecar + branch-build CI

## Problem

The bitrate-based pseudo-SPL meter (`audio_level_meter.dart`) does not react to
real sound: AAC encoders allocate bits by spectral complexity under tight rate
control, so crying/talking barely moves `audio-bitrate`. The only trustworthy
loudness signal is decoded PCM, which libmpv does not expose and the stripped
FFmpeg build cannot analyze (no `astats`/`ebur128`, lavfi `|` bug).

## Approach (researched + user-approved)

**Android analyzer sidecar, playback untouched.** Per camera, a second
audio-only RTSP session via media3 ExoPlayer (RTSP module, forced TCP),
decoded PCM tapped with `TeeAudioProcessor` → RMS/peak dBFS at ~10 Hz →
`EventChannel` to Dart. Playback keeps the battle-tested media_kit/mpv path;
the sidecar is best-effort — any failure degrades to the existing bitrate
proxy (CLAUDE.md defensive contract).

Key verified facts:
- media3 stable 1.10.1; RTSP module supports forced interleaved TCP and
  custom `SocketFactory` (TLS for `rtsps://` manual URLs, go2rtc "rtspx" trick).
- Unifi consoles serve plain RTSP on :7447 (`rtspsToRtsp()` already exists and
  is the proven Windows playback path) — the sidecar's default transport.
- ExoPlayer applies volume at the AudioTrack (after processors), so a muted
  (volume-0) sidecar still taps full-scale PCM.
- Flutter default minSdk is 24 ≥ media3's required 23.

## Tasks

1. **feat(metering): Kotlin analyzer sidecar** — media3 deps in
   `android/app/build.gradle.kts`; `levelmeter/` package: `PcmLevelTap`
   (AudioBufferSink → windowed RMS/peak dBFS), `CameraLevelAnalyzer`
   (audio-only ExoPlayer, candidate URL cycling, exponential backoff,
   PCM-stall watchdog), `LevelMeterController` (singleton; MethodChannel
   `roomtone/level_meter`: start/startCamera/stopCamera/stopAll; EventChannel
   `roomtone/level_meter/events`); MainActivity wiring.

2. **feat(metering): Dart integration with fallback** —
   `services/native_level_meter.dart` (channel wrapper + defensive event
   parsing); `helpers/level_dynamics.dart` (dBFS→0..1 mapping; ActivityDetector:
   attack/release-smoothed level over a rolling-percentile noise floor,
   activity = excess-dB/30 so the existing sensitivity slider semantics hold);
   `helpers/meter_urls.dart` (sidecar candidate URLs, low quality preferred,
   rtsps→rtsp rewrite for Unifi); provider lifecycle (start/stop/add/remove) +
   poll uses fresh native dBFS, falls back to bitrate when stale/absent;
   StreamInfo gains `audioDbfs`/`meterSource` shown in the debug panel.

3. **test(metering): unit tests** — level_dynamics (mapping bounds, floor
   adaptation, activity attack/decay, hysteresis-by-threshold), meter_urls
   (rewrites, ordering, manual passthrough), native event parsing.

4. **ci(build): branch-build workflow** — `workflow_dispatch` (+ `build/**`
   push) → signed release APK (debug-signing fallback when secrets absent),
   versioned `0.0.0-<branch>.<sha>` with epoch-minute versionCode, uploaded as
   workflow artifact. Lets anyone install a build from any branch pre-merge,
   no release.

5. **docs: CLAUDE.md metering section** — replace bitrate-proxy row with the
   sidecar architecture + fallback.

## Verification

- `flutter analyze --fatal-infos` clean; `flutter test` green (no Android SDK
  in this container — Kotlin compiles are verified by dispatching the new
  branch-build workflow on CI).
- Branch-build workflow run produces an installable APK artifact.

## Deviations

- Executes on session branch `claude/spl-metering-activity-detection-3yhvzq`
  (session git requirement) instead of a GSD-generated branch; inline
  execution (design fully resolved in-session, hook support unavailable).
