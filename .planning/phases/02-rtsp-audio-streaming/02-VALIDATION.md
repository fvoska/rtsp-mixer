---
phase: 2
slug: rtsp-audio-streaming
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-04-03
---

# Phase 2 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | flutter_test (built-in) |
| **Config file** | `pubspec.yaml` (dev_dependencies) |
| **Quick run command** | `flutter test test/features/monitoring/` |
| **Full suite command** | `flutter test` |
| **Estimated runtime** | ~15 seconds |

---

## Sampling Rate

- **After every task commit:** `flutter test test/features/monitoring/`
- **After every plan wave:** `flutter test`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 02-01-T1a | 01 | 1 | STRM-01 | unit | `flutter test test/features/monitoring/rtsp_url_test.dart` | Wave 0 | pending |
| 02-01-T1b | 01 | 1 | STRM-03 | unit | `flutter test test/features/monitoring/pan_filter_test.dart` | Wave 0 | pending |
| 02-01-T2 | 01 | 1 | STRM-02 | unit | `flutter test test/features/monitoring/player_state_test.dart` | Wave 0 | pending |
| 02-02-T1 | 02 | 2 | STRM-02 | unit | `flutter test test/features/monitoring/audio_player_provider_test.dart` | Wave 0 | pending |
| 02-02-T1 | 02 | 2 | STRM-01 (vid=no) | manual | See Manual-Only Verifications | N/A | pending |

*Status: pending / green / red / flaky*

---

## Wave 0 Requirements

- [ ] `test/features/monitoring/rtsp_url_test.dart` -- covers STRM-01 URL construction
- [ ] `test/features/monitoring/pan_filter_test.dart` -- covers STRM-03 pan filter string generation and clamping
- [ ] `test/features/monitoring/player_state_test.dart` -- covers STRM-02 volume/mute state, effectiveVolume logic
- [ ] `test/features/monitoring/audio_player_provider_test.dart` -- covers STRM-02 volume/pan/mute state transitions (pure state tests)

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Audio plays from RTSP stream | STRM-01 | Requires real RTSP stream from Unifi camera | Connect to camera, verify audio output from device speaker |
| `setProperty('vid', 'no')` called on each Player | STRM-01 | media_kit `Player` and `NativePlayer` are concrete classes with native (C/libmpv) bindings. Mocking via mockito requires codegen against native interop that is fragile and breaks across media_kit versions. Source grep + manual CPU verification is more reliable. | 1. `grep -n "setProperty.*vid.*no" lib/features/monitoring/providers/audio_player_provider.dart` confirms call exists. 2. During live test, check Activity Monitor -- CPU < 10% confirms no video decoding. |
| Stereo panning audible | STRM-03 | Requires headphones to verify L/R balance | Set pan to -1.0, verify audio in left ear only; set to 1.0, verify right |
| No video decoded (CPU) | STRM-01 | Requires CPU monitoring | Check Activity Monitor / Android profiler during playback -- CPU < 10% |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or are explicitly listed as Manual-Only with rationale
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all test file dependencies
- [x] No watch-mode flags
- [x] Feedback latency < 15s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
