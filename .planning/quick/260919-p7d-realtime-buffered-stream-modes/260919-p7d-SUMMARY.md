---
phase: quick-260919-p7d
plan: 01
subsystem: monitoring
status: complete
tags: [mpv, live-edge, latency, drift, scaletempo2, cache-pause, settings, reconnect]
requires:
  - phase: 04-reliability-overnight-monitoring
    provides: DriftWatchdog / ReconnectSupervisor fed from the poll loop
provides:
  - Two-tier live-edge guard: speed catch-up (mpv `speed` + built-in scaletempo2) first, stop+open only past a 10 s hard limit
  - StreamMode.realtime / StreamMode.buffered settings with per-mode mpv cache-pause tuning
  - Settings UI: Stream mode segmented control + Buffer delay slider (0.5–5 s)
commits:
  - 1d6dfb4 feat(settings): add Realtime/Buffered stream mode and buffered delay settings
  - c76357b fix(monitoring): catch up to the live edge with a speed nudge instead of reconnecting
  - 1d3191c fix(monitoring): keep the PCM level tap on realtime tuning in buffered mode
  - fffc7b9 feat(settings): Realtime / Buffered stream mode control with a buffer delay slider
---

# Quick task 260919-p7d: live-edge catch-up + Realtime/Buffered stream modes

## Why the drift reconnects were so frequent

- `DriftWatchdog` compared `demuxer-cache-duration` (the packet cache) against
  `audioBufferSeconds + 1.0` (the *audio output* buffer). Unrelated buffers; at
  the "low latency" slider position the margin over the cache's normal depth
  was 0.2 s.
- `demuxer-readahead-secs=1` was inert: per the mpv manual, with `cache=yes`
  the option "is mostly ignored" because `cache-secs` (default very high)
  overrides it, so the cache was bounded only by `demuxer-max-bytes`.
- A live stream's cache only grows (mpv reads as fast as the network delivers,
  plays at exactly 1x). Every stall — Doze, audio-focus duck, WiFi hiccup, the
  NVR's start-up burst — left a permanent residue. Once it crossed the margin
  the app stop+opened the RTSP session every 30 s cooldown for a stream that
  was fine: 2–4 s gap, "reconnecting" status, health-summary downtime, level
  tracker and PCM tap reset.
- `demuxer-max-back-bytes=0` was justified by a wrong model (the back-buffer
  holds already-played packets; it never replays them). Kept, since it costs
  nothing, but the comment is corrected.

## What mpv offers natively (used instead of custom work)

- `speed` slightly above 1 with `audio-pitch-correction` (default on), which
  auto-inserts mpv's **built-in** `scaletempo2` WSOLA filter — mpv C code,
  not an FFmpeg lavfi filter, so the stripped FFmpeg build does not matter.
  The mpv manual's low-latency section recommends exactly this for live
  sources; media_kit's `Player.setRate` relies on the same path.
- `cache-pause` / `cache-pause-initial` / `cache-pause-wait=<s>`: mpv's own
  jitter buffer (pause on underrun until N seconds are cached).
- `fflags=+nobuffer` from mpv's built-in low-latency profile to shrink the
  probe backlog at open.
- Not used: `drop-buffers` (experimental, "very disruptive"), cache seeks
  (RTSP PLAY with Range against the NVR is untested and could kill the
  stream), `untimed` (breaks with audio).

## What changed

- `DriftWatchdog`: tier 1 engages `onSetSpeed(cam, 1.1)` (1.05 buffered)
  when cache > target + margin, returns to 1.0 at target (hysteresis,
  transitions only). Tier 2 fires the existing 'drift' reconnect only when
  cache > target + 10 s for 4 s, 30 s cooldown. `reset` clears catch-up state.
- `_applyPlaybackTuning`: `cache-on-disk=no` (media_kit defaults it on),
  `demuxer-max-bytes=8MiB` so a backlog stays measurable, `speed=1.0` +
  `audio-pitch-correction=yes` on every (re)open; realtime → `cache-pause=no`,
  `cache-pause-initial=no`, lavf `nobuffer`; buffered → `cache-pause=yes`,
  `cache-pause-initial=yes`, `cache-pause-wait=<delay>`. The PCM tap always
  gets the realtime variant (`forTap: true`).
- Settings: `StreamMode` (default realtime) + `bufferedDelaySeconds`
  (default 2.0, clamped 0.5–5.0); changes restart the streams.
- UI: "Stream mode" segmented control with trade-off subtitles; "Buffer
  delay" slider visible in Buffered mode; "Audio buffer" slider kept (it is
  the AO buffer).
- Docs: README bullets, CLAUDE.md "Live edge, latency and stream modes".

## Verification

- `flutter analyze --fatal-infos`: clean.
- `flutter test`: 593 passed (drift watchdog 21 tests rewritten for the
  two-tier API; settings provider +7; new stream_mode_toggle widget test +4).
- Not verified in-session (no device): that this media_kit libmpv build
  honours `speed` on a live RTSP stream with scaletempo2. If it does not,
  the failure mode is logged and non-fatal (`_setPlaybackSpeed` is guarded),
  and the 10 s hard-limit resync still bounds the lag. Watch the `DRIFT`
  log lines for `catch-up 1.1x` followed by `at live edge` on a real phone.
