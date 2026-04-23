---
phase: 4
slug: reliability-overnight-monitoring
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-23
---

# Phase 4 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | `flutter_test` (package:test) + `fake_async ^1.3.0` dev-dep for deterministic timer tests |
| **Config file** | `pubspec.yaml` (dev_dependencies section) |
| **Quick run command** | `flutter test --reporter expanded --exclude-tags=slow test/features/monitoring/` |
| **Full suite command** | `flutter test` |
| **Estimated runtime** | Quick: ~6s · Full: ~15s |

---

## Sampling Rate

- **After every task commit:** Run `flutter test test/features/monitoring/` for the files changed in that task
- **After every plan wave:** Run `flutter test` (full suite)
- **Before `/gsd-verify-work`:** Full suite must be green AND at least one overnight on-device run completed
- **Max feedback latency:** ~15 seconds for the full suite

---

## Per-Task Verification Map

Test infrastructure is shared; individual task mapping is finalized by the planner. Categories from RESEARCH.md §7:

| Test category | Requirement | Test Type | Automated Command |
|---------------|-------------|-----------|-------------------|
| Backoff math (exponential, ±20% jitter, cap at 30s) | RELY-01 | unit | `flutter test test/features/monitoring/reconnect/backoff_test.dart` |
| Reconnect trigger dedupe (multiple triggers within ms → single attempt) | RELY-01 | unit | `flutter test test/features/monitoring/reconnect/trigger_dedupe_test.dart` |
| Zombie detector quorum logic (≥2 of 4 signals) | RELY-03 | unit | `flutter test test/features/monitoring/zombie/quorum_test.dart` |
| Zombie signal false-positive at stream start (bitrate=0 + no audioParams must NOT trigger within first 3s) | RELY-03 | unit | same file |
| HealthEvent stream 1000-event cap (append 1,001 events → first is dropped) | MNTR-01 | unit | `flutter test test/features/monitoring/health/event_stream_cap_test.dart` |
| WiFi debounce (3 rapid flaps collapse to one reconnect event) | RELY-01 | unit | `flutter test test/features/monitoring/reconnect/wifi_debounce_test.dart` |
| 5-minute alert timer fires after threshold, resets on recovery | RELY-01 | unit | `flutter test test/features/monitoring/alerts/alert_timer_test.dart` |
| 5-minute alert is one-shot per outage cycle | RELY-01 | unit | same file |
| State machine transitions: playing → error → reconnecting → playing | RELY-02 | unit | `flutter test test/features/monitoring/reconnect/state_machine_test.dart` |
| CameraConnectionStatus enum has `reconnecting` state | RELY-02 | unit | `flutter test test/features/monitoring/models/player_state_test.dart` |
| CameraAudioCard renders amber tint + spinner for reconnecting | RELY-02 | widget | `flutter test test/features/monitoring/widgets/camera_audio_card_test.dart` |
| HealthSummaryScreen renders event list + per-camera counters | MNTR-01 | widget | `flutter test test/features/monitoring/screens/health_summary_screen_test.dart` |
| Reconnect loop survives an exception thrown inside the retry timer | CLAUDE.md §Conventions | unit | `flutter test test/features/monitoring/reconnect/defensive_recovery_test.dart` |
| `flutter analyze` passes with zero `lib/` issues | n/a | static | `flutter analyze --no-preamble lib test` |

*Status column is filled by executor at commit time.*

---

## Wave 0 Requirements

- [ ] `pubspec.yaml` — add `connectivity_plus: ^7.1.1`, `flutter_local_notifications: ^19.0.0` (pinned below 20.x — project is on Dart 3.9.2 and 20.x requires Dart 3.10), and dev-dep `fake_async: ^1.3.0`
- [ ] `test/features/monitoring/reconnect/` — directory + stub files for: `backoff_test.dart`, `trigger_dedupe_test.dart`, `wifi_debounce_test.dart`, `state_machine_test.dart`, `defensive_recovery_test.dart`
- [ ] `test/features/monitoring/zombie/quorum_test.dart` — stub
- [ ] `test/features/monitoring/health/event_stream_cap_test.dart` — stub
- [ ] `test/features/monitoring/alerts/alert_timer_test.dart` — stub
- [ ] `test/features/monitoring/widgets/camera_audio_card_test.dart` — stub (may already exist; if so, extend with reconnecting-state case)
- [ ] `test/features/monitoring/screens/health_summary_screen_test.dart` — stub
- [ ] `test/features/monitoring/models/player_state_test.dart` — stub

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Overnight foreground service survival (8+ hours, screen off, charging) | RELY-01, RELY-03 | Doze mode interaction with `Timer.periodic` cannot be reproduced in emulator. Per RESEARCH.md §8 assumption A2 (CRITICAL risk). | Start monitoring on physical device, lock screen, leave charging overnight; next morning check: (a) app still running, (b) audio resumed after any WiFi blips, (c) HealthSummaryScreen shows expected event count, (d) no ANR / force-stop notifications |
| Real WiFi drop/reconnect triggers reconnect | RELY-01 | Emulated WiFi drops don't mirror real AP behavior (DHCP renewal, re-auth) | Start monitoring; on the phone, disable WiFi for 30s, re-enable; verify both cameras return to playing and `wifi_dropped`/`wifi_reconnected` events appear in health summary |
| Zombie stream recovery on real camera | RELY-03 | Requires reproducing a TCP-open/no-audio condition which typically happens after camera firmware updates or NVR hiccups | Start monitoring; block RTSP port via phone firewall (or pause camera mic in Protect UI); after 60s verify `zombie_detected` event + card shows reconnecting; unblock/resume; verify recovery |
| 5-minute push notification fires and wakes screen | RELY-01 (D-04) | flutter_local_notifications `Importance.max` behavior under Doze depends on OEM heads-up policy | Start monitoring; kill one camera's RTSP path; wait 5 minutes with phone locked/idle; verify local notification appears and makes sound/vibration per channel config |
| Notification Pause action no longer breaks reconnect loop | RELY-01, BGND-01 | Requires full foreground-service lifecycle | Tap Pause notification button → verify all cameras stop; tap Resume (or reopen app) → verify cameras reconnect cleanly |
| Both-cameras-down scenario fires per-camera alerts (not one coalesced) | RELY-01 (D-04 per-camera scope) | Needs two cameras actually down at once | Pull power on both cameras / disable both in Protect; verify two separate notifications fire at their individual 5-min thresholds |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] Overnight on-device run (RESEARCH.md §8 A2) completed and captured
- [ ] `nyquist_compliant: true` set in frontmatter after all boxes checked

**Approval:** pending
