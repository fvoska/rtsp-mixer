---
phase: quick-260919-foa
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
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
  - lib/features/monitoring/services/pcm_fifo.dart
  - lib/features/monitoring/services/pcm_level_tap.dart
  - lib/features/monitoring/helpers/pcm_level.dart
  - test/features/monitoring/helpers/pcm_level_test.dart
  - test/features/monitoring/services/pcm_fifo_test.dart
  - pubspec.yaml
autonomous: true
must_haves:
  truths:
    - "The card border and halo are a direct, smooth function of the current sound level, not of how much the level swung recently"
    - "The waveform chart draws the same level series that drives the border, over the last 60 s"
    - "A quiet nursery reads as quiet: the level is measured relative to an adaptive noise floor, so a steady low bitrate does not glow"
    - "No exception thrown by the meter can reach the poll loop or build"
  artifacts:
    - path: lib/features/monitoring/helpers/audio_level_meter.dart
      provides: AudioLevelTracker (noise-floor-relative, smoothed level) + appendLevel
    - path: lib/features/monitoring/widgets/camera_audio_card.dart
      provides: level-driven border/halo + 60 s waveform painter with threshold guides
  key_links:
    - from: audio_player_provider._pollAudioLevels
      to: AudioLevelTracker.update
      via: per-camera tracker map, fed every 250 ms
    - from: CameraAudioState.audioLevel / levelHistory
      to: CameraAudioCard border + _WaveformChart
      via: same value appended to the history each tick
---

<objective>
Replace the variation-based activity monitor with a single, smoothed, noise-floor-relative
sound level that drives both the card border/halo and a 60 s waveform history.

Purpose: the current border lights on *peak-to-trough variation* of a coarse absolute
bitrate mapping, so it flickers on jitter and switches off during a steady cry, while
the 10 s / 20-bar chart is too coarse to read as a waveform. Parents need the card to
brighten as the room gets louder and dim as it quiets, and to see the last minute at a
glance.

Output: one level signal (0..1 above the room's quiet floor) polled 4x/s, an envelope
with fast attack / slow release, a border whose alpha and glow follow that level, and a
mirrored 60 s waveform of the same samples with threshold guide lines.
</objective>

<context>
@CLAUDE.md
@lib/features/monitoring/helpers/audio_level_meter.dart
@lib/features/monitoring/providers/audio_player_provider.dart
@lib/features/monitoring/widgets/camera_audio_card.dart
</context>

<tasks>

<task type="auto">
  <name>Task 1: AudioLevelTracker — noise-floor-relative smoothed level (pure Dart)</name>
  <files>lib/features/monitoring/helpers/audio_level_meter.dart, test/features/monitoring/helpers/audio_level_meter_test.dart</files>
  <action>
    Rewrite the helper around a per-camera `AudioLevelTracker`:
    - `bitrateToDb(bps)` = 10·log10(bps), null for garbage (null/NaN/inf/≤0).
    - `update({bps, flowing, dtSeconds})` returns the display level 0..1:
      1. Short EMA on dB (attack τ ≈ 0.4 s) to suppress per-packet jitter.
      2. Calibration window: once per second push the second's minimum smoothed dB into a
         5-minute ring; floor = min of ring, ceiling = max of ring. Skip the first 2 s of a
         fresh stream (mpv's first bitrate samples are unreliable) and every !flowing tick.
      3. Span = clamp(ceiling − floor, 6 dB, 24 dB); raw = clamp((smoothed − floor) / span).
      4. Envelope: rises immediately, falls with release τ ≈ 0.8 s. !flowing → target 0
         (decays out); flowing but no bitrate yet → hold the previous level.
    - Keep `appendLevel`; capacity becomes 240 (60 s at 250 ms). Drop `bitrateToLevel`
      and `recentVariation`.
    - Everything guarded so garbage input can never throw or produce NaN.
    Unit tests: dB mapping, warm-up, floor tracking (quiet baseline reads ≈ 0, a +12 dB
    burst reads ≈ 1), release decay, !flowing decay, hold-on-null, NaN safety,
    appendLevel eviction.
  </action>
  <verify>flutter test test/features/monitoring/helpers</verify>
  <done>Tracker is pure Dart (dart:math + dart:collection only), tests green.</done>
</task>

<task type="auto">
  <name>Task 2: Wire the tracker into the poll loop and state</name>
  <files>lib/features/monitoring/models/player_state.dart, lib/features/monitoring/providers/audio_player_provider.dart, lib/core/providers/settings_provider.dart, lib/features/settings/screens/settings_screen.dart, lib/features/monitoring/screens/monitoring_screen.dart, test/core/providers/settings_provider_test.dart</files>
  <action>
    - Remove `CameraAudioState.audioActivity`; `audioLevel` becomes the tracker's display
      level and `levelHistory` the rolling 60 s list of that same value.
    - Poll every 250 ms (`kLevelPollInterval`). Read only audio-pts / audio-bitrate /
      demuxer-cache-duration each tick; the nine metadata properties every 8th tick (2 s).
      Watchdog ticks keep receiving the real interval in ms, so their thresholds are
      unchanged.
    - `_levelTrackers` map mirrors `_lastAudioPts` lifecycle exactly (clear on stop /
      dispose, remove on camera removal and on successful reconnect).
    - Settings: rename `activityThreshold` → `levelThreshold` (persisted under a NEW
      JSON key `levelThreshold`, default 0.25, ignore the legacy key so stale
      variation-era values don't carry over). Slider 0.05..0.6 with copy describing
      "how far above the room's quiet level".
  </action>
  <verify>flutter analyze --fatal-infos && flutter test test/core/providers</verify>
  <done>Provider compiles, no reference to audioActivity/recentVariation remains, settings tests green.</done>
</task>

<task type="auto">
  <name>Task 3: Level-driven border + 60 s waveform on the card</name>
  <files>lib/features/monitoring/widgets/camera_audio_card.dart, test/features/monitoring/widgets/camera_audio_card_test.dart, test/core/theme/light_theme_smoke_test.dart, README.md, CLAUDE.md</files>
  <action>
    - Border/halo intensity = smoothstep of (audioLevel − threshold) / (1 − threshold);
      constant 2 px width (a width change would shift layout), alpha + glow scale with it.
      Keep the NaN/inf/threshold≥1 degradation path.
    - `_WaveformChart` draws the full history (240 slots, newest right) as two filled
      paths — samples below the threshold in primary, above it in the live colour — plus
      mirrored threshold guide lines, 10 s tick marks and a "60 s" caption. Identity-based
      shouldRepaint + threshold/colour comparison.
    - Update widget tests to the level semantics, README blurb and CLAUDE.md metering row.
  </action>
  <verify>flutter analyze --fatal-infos && flutter test</verify>
  <done>Full suite green; analyze clean with --fatal-infos.</done>
</task>

<task type="auto">
  <name>Task 4: Real loudness from a PCM tap (user feedback: bitrate does not vary enough)</name>
  <files>lib/features/monitoring/services/pcm_fifo.dart, lib/features/monitoring/services/pcm_level_tap.dart, lib/features/monitoring/helpers/pcm_level.dart, lib/features/monitoring/helpers/audio_level_meter.dart, lib/features/monitoring/providers/audio_player_provider.dart, lib/features/monitoring/models/player_state.dart, lib/features/monitoring/widgets/camera_audio_card.dart, pubspec.yaml, tests</files>
  <action>
    Hardware feedback: the AAC bitrate is near-constant, so Tasks 1-3 had a good
    pipeline on a dead signal. Verified by reading the configure string inside the
    Android `libmpv.so` (media-kit libmpv-android-video-build v1.1.7) that FFmpeg
    is built with `--disable-filters` (only overlay/equalizer re-enabled) — no
    analysis filter will ever exist — but mpv's `ao=pcm` writer is compiled in.
    - `PcmFifo`: libc FFI (mkfifo/open O_NONBLOCK/read/close/unlink, SIGPIPE
      ignored) — non-blocking named-pipe reader polled from the level tick.
    - `PcmLevelMeter`: s16-LE mono → loudest 50 ms RMS window per tick in dBFS,
      carrying partial windows across calls.
    - `PcmLevelTap`: a second silent `Player` per camera with `ao=pcm`,
      `ao-pcm-file=<fifo>`, `ao-pcm-waveheader=no`, `audio-format=s16`,
      `audio-channels=mono`, `audio-samplerate=8000`, `vid=no`; teardown disposes
      the writer while draining, then closes the reader (never the reverse).
    - Tracker takes dB directly; presets `.pcm()` (span 30..50 dB) and
      `.bitrate()` (6..24 dB). Provider swaps tracker on source change, manages tap
      lifecycle (start when live, drop on URL change / failure / 25 s no data /
      10 s stall / not live / reconnect / removal / stop, 20 s retry cooldown),
      and falls back to bitrate whenever the tap is not delivering.
    - `CameraAudioState.levelSource` + `levelDb`; details panel shows "Meter".
  </action>
  <verify>flutter analyze --fatal-infos && flutter test; plus a scratch e2e against a real `mpv` binary (installed in the session) proving the flags and pipe path</verify>
  <done>Suite green; e2e produced exactly 9 s × 16 000 B and a 44 dB loud/quiet swing.</done>
</task>

</tasks>

<verification>
- `flutter analyze --fatal-infos` clean
- `flutter test` green
- grep: no `audioActivity`, `recentVariation`, `bitrateToLevel`, `activityThreshold` in lib/ or test/
</verification>

<success_criteria>
Border brightness follows the smoothed sound level in real time; the waveform is the
same series over 60 s with the trigger threshold visible; a quiet room stays dark.
</success_criteria>
