---
phase: 2
slug: rtsp-audio-streaming
status: draft
nyquist_compliant: false
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
| **Quick run command** | `flutter test --tags unit` |
| **Full suite command** | `flutter test` |
| **Estimated runtime** | ~15 seconds |

---

## Sampling Rate

- **After every task commit:** Run `flutter test --tags unit`
- **After every plan wave:** Run `flutter test`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 02-01-01 | 01 | 0 | STRM-01 | unit | `flutter test test/services/audio_player_service_test.dart` | ❌ W0 | ⬜ pending |
| 02-01-02 | 01 | 1 | STRM-02 | unit | `flutter test test/services/audio_player_service_test.dart` | ❌ W0 | ⬜ pending |
| 02-01-03 | 01 | 1 | STRM-03 | unit | `flutter test test/services/audio_player_service_test.dart` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/services/audio_player_service_test.dart` — stubs for STRM-01, STRM-02, STRM-03
- [ ] Test helpers for mocking media_kit Player instances

*Wave 0 stubs will be refined once plans are finalized.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Audio plays from RTSP stream | STRM-01 | Requires real RTSP stream from Unifi camera | Connect to camera, verify audio output from device speaker |
| Stereo panning audible | STRM-03 | Requires headphones to verify L/R balance | Set pan to -1.0, verify audio in left ear only; set to 1.0, verify right |
| No video decoded | STRM-01 | Requires CPU monitoring | Check Activity Monitor / Android profiler during playback — CPU < 10% |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
