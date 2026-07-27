---
id: 260727-pzo
status: complete
completed: 2026-07-27
---

# Quick Task 260727-pzo: Native PCM level metering sidecar + branch-build CI — Summary

## What changed

**Native Android analyzer sidecar (Kotlin, `android/.../levelmeter/`):**
- `PcmLevelTap` — `TeeAudioProcessor.AudioBufferSink` reducing decoded PCM to
  ~100 ms RMS/peak windows in dBFS (floor −100, allocation-light, audio thread).
- `CameraLevelAnalyzer` — one audio-only ExoPlayer (media3 1.10.1 RTSP module,
  forced TCP interleave, volume 0, no video renderer) per camera; candidate URL
  cycling, 2s→60s exponential backoff, 20s PCM-stall watchdog; RTSP-over-TLS
  path for manual `rtsps://` URLs (trust-all, matching the mpv trust model).
- `LevelMeterController` — process-wide singleton owning analyzers +
  MethodChannel `roomtone/level_meter` (start/startCamera/stopCamera/stopAll)
  and EventChannel `roomtone/level_meter/events`; idempotent `attach` from
  `MainActivity.configureFlutterEngine`.

**Dart integration (bitrate proxy kept as fallback):**
- `services/native_level_meter.dart` — channel wrapper, Android-gated,
  never-throws; total event parser `nativeLevelEventFromDynamic`.
- `helpers/level_dynamics.dart` — `dbfsToLevel` (−60..−5 dBFS → 0..1) and
  `ActivityDetector` (attack 250 ms / release 2.5 s smoothing; noise floor =
  10th percentile of per-second minima over 5 min, clamped [−90, −20];
  activity = excess-dB/30 so the existing sensitivity slider semantics hold).
- `helpers/meter_urls.dart` — sidecar candidates: low quality preferred,
  Unifi URLs rewritten to plain `rtsp://:7447`, manual URLs verbatim.
- `audio_player_provider.dart` — sidecar lifecycle tied to
  start/stop/add/remove; poll prefers fresh (≤3 s) native dBFS, falls back to
  bitrate; PTS flow keeps silence/zombie roles; `StreamInfo.audioDbfs` +
  `meterSource` surfaced in the card's debug panel.

**CI:** `.github/workflows/branch-build.yml` — `workflow_dispatch` on any ref
(+ auto-build on `build/**` pushes); signed release APK (debug fallback),
version `0.0.0-<branch>.<sha>`, epoch-minute versionCode, 30-day artifact.

**Docs:** CLAUDE.md metering stack section rewritten (sidecar + fallback).

## Commits

- `6e486c0` feat(metering): add native Android PCM level analyzer sidecar
- `68e2496` feat(metering): drive level meter and activity from native dBFS with bitrate fallback
- `8fff8df` test(metering): unit tests for dBFS mapping, activity detector, meter URLs, and event parsing
- `f26c788` ci(build): add on-demand branch-build workflow producing installable APKs
- `dd37966` docs(stack): document native PCM metering sidecar architecture and bitrate fallback

## Verification

- `flutter analyze --fatal-infos`: clean.
- `flutter test`: 496 passing (24 new).
- Kotlin/gradle compile: no Android SDK in the session container — verified by
  dispatching the new branch-build workflow on CI (also produces the first
  installable test APK for on-device validation).

## On-device validation still needed (no cameras/device in CI)

1. Meter row in debug panel shows `native · x.x dBFS` on both cameras.
2. Meter tracks talking/crying near the camera; border activity fires per the
   sensitivity slider; a running fan stops triggering within ~5 min.
3. Sidecar survives console reboot / WiFi drop (status `retrying` → `active`),
   with playback unaffected throughout.
