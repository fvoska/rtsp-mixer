---
phase: 04-reliability-overnight-monitoring
verified: 2026-04-28T21:16:14Z
status: human_needed
score: 4/4 must-haves verified (automated)
overrides_applied: 0
human_verification:
  - test: "Overnight foreground service survival (8+ hours, screen off, charging)"
    expected: "App still running in the morning; HealthSummaryScreen shows expected event count; audio resumes after any WiFi blips; no ANR / force-stop notifications"
    why_human: "Doze mode interaction with Timer.periodic cannot be reproduced in emulator (RESEARCH.md §8 A2 / VALIDATION.md Manual-Only #1). Real-device 8h soak required."
  - test: "Real WiFi drop/reconnect triggers reconnect"
    expected: "Both cameras return to playing after WiFi toggle; wifiDropped + wifiReconnected events appear in HealthSummaryScreen; immediate-mode bypass cancels the pending backoff timer"
    why_human: "Emulated WiFi drops do not mirror real AP behavior (DHCP renewal, re-auth). Verifies CR-02 fix end-to-end."
  - test: "Zombie stream recovery on real camera"
    expected: "After 60s of TCP-open/no-audio, zombieDetected event fires; card flips to reconnecting; recovery on unblock; CR-01 fix means a healthy stream does NOT false-fire after ~60s"
    why_human: "Requires reproducing TCP-open/no-audio condition (block RTSP port via firewall or pause camera mic in Protect UI). Also exercises the CR-01 PTS-stall-necessary regression in real conditions."
  - test: "5-minute push notification fires and wakes screen (D-04)"
    expected: "After 5 minutes of continuous non-playing, local notification appears with 'Camera offline: {name}' title; sound + vibration honor channel config; alertFired event recorded even if notification suppressed by OEM Doze policy"
    why_human: "flutter_local_notifications Importance.max behavior under Doze depends on OEM heads-up policy. Requires real device + 5-minute wait."
  - test: "Notification permission denied — alertFired event still recorded"
    expected: "After denying POST_NOTIFICATIONS, induce a 5-minute outage; verify HealthSummaryScreen shows alertFired even though no notification appeared (T-04-24 mitigation)"
    why_human: "Permission denial UI is OS-level; requires manual deny + observe."
  - test: "Both-cameras-down fires per-camera alerts (not coalesced)"
    expected: "With both cameras offline simultaneously, two separate alertFired events at independent 5-minute thresholds; two separate notifications (different cameraId.hashCode IDs)"
    why_human: "Needs two real cameras down at once (pull power on both / disable both in Protect UI)."
  - test: "Initial open failure (WR-01) — alert + supervisor takeover"
    expected: "If startMonitoring's first player.open() throws (e.g., wrong RTSP URL or camera offline at start), the camera enters error state AND the 5-min alert clock arms AND the supervisor begins retrying with backoff. After 5 minutes the alertFired notification appears."
    why_human: "Reproducing first-open failure requires staged camera environment (blocked port at start). Verifies WR-01 fix end-to-end."
  - test: "Cellular-only startup (WR-02) — no spurious wifiDropped at t≈0"
    expected: "Launch app on a phone with WiFi off / cellular only. HealthSummaryScreen does NOT show a wifiDropped event at session start. Toggling WiFi on later DOES record wifiReconnected."
    why_human: "Requires controlling phone connectivity at boot; verifies the Connectivity().checkConnectivity() seed in ConnectivityListener.start()."
---

# Phase 4: Reliability + Overnight Monitoring — Verification Report

**Phase Goal:** "Auto-reconnect on stream drops, connection status UI, watchdog, and overnight health summary"
**Verified:** 2026-04-28T21:16:14Z
**Status:** human_needed (automated checks all pass; routine manual on-device verifications remain)
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths (mapped to ROADMAP success criteria)

| # | Truth (ROADMAP success criterion) | Status | Evidence |
|---|------------------------------------|--------|----------|
| 1 | App automatically reconnects when a stream drops (camera reboot, WiFi blip) without user intervention | VERIFIED (auto) | `ReconnectSupervisor` (lib/features/monitoring/services/reconnect_supervisor.dart) implements exponential backoff (1/2/4/8/16/30s) with ±20% jitter + retry-forever loop. Triggered by player.stream.error (line 162), player.stream.completed (line 185), zombie watchdog onFire (audio_player_provider.dart:51), WiFi reconnect (line 764), and initial open failure (line 403). 8 reconnect-related test files pass deterministically (backoff_test, trigger_dedupe_test, state_machine_test, defensive_recovery_test, wifi_debounce_test). CR-02 fix (immediate-mode reorder, supervisor.dart lines 79-104) confirms WiFi-back actually bypasses pending backoff — proven by trigger_dedupe_test.dart's CR-02 regression test. |
| 2 | User can see per-camera connection status at a glance (connecting, live, reconnecting, error) | VERIFIED (auto) | `CameraConnectionStatus` enum has 5 variants (player_state.dart). `CameraAudioCard` (camera_audio_card.dart) renders `reconnecting` with `colorScheme.tertiary` status dot (line 142), `tertiaryContainer @ 0.3` header tint (line 124), 14×14 `CircularProgressIndicator` (lines 177-179), and `Reconnecting…` text (line 187, U+2026 ellipsis). Linear progress bar reserved for `connecting` only. `Connecting…` copy normalized (line 194). 6 widget tests in camera_audio_card_test.dart cover all branches + D-11 attempt/retry/countdown anti-pattern guard. |
| 3 | App detects and recovers from zombie streams where TCP is open but no audio data arrives | VERIFIED (auto) | `ZombieWatchdog` (zombie_watchdog.dart) implements 4-signal quorum with PTS-stall as a NECESSARY condition (CR-01 fix, lines 101-108). Wired into `_pollAudioLevels` (audio_player_provider.dart:501, 537, 584), `player.stream.buffering` (line 207), and `player.stream.audioParams` (line 241). On fire → `_reconnectSupervisor.requestReconnect(cause: 'zombie')` (line 50). 9 unit tests in quorum_test.dart, including the 240-tick healthy-stream regression test (line 64) that asserts the watchdog does NOT fire on a stream with healthy PTS but stale buffering/audioParams counters. Reset on successful reconnect via `_applyReconnectStatus` (line 710). |
| 4 | User can view an overnight health summary showing uptime, reconnection count, and stream health events | VERIFIED (auto) | `HealthSummaryScreen` (health_summary_screen.dart) is a `ConsumerWidget` that watches `healthEventsProvider` (line 20) and `audioPlayerProvider` (line 21). Renders session uptime (line 48 AppBar title 'Health summary'), per-camera Reconnects + Downtime tiles, chronological event log via `events.reversed.toList()` (line 82, newest-on-top). Empty state 'Monitoring just started' (line 297) + Icons.health_and_safety_outlined (line 291). Stopped-session banner (line 272). Severity-mapped icons + colors per UI-SPEC. Accessed via AppBar IconButton on MonitoringScreen (monitoring_screen.dart:157, `Icons.monitor_heart_outlined` + 'Open health summary' tooltip, opens via Navigator.push + MaterialPageRoute). 7 widget tests in health_summary_screen_test.dart. |

**Score:** 4/4 truths automated-verified · 8 manual-only verifications outstanding (per VALIDATION.md Manual-Only Verifications + 2 derived from CR-fix regression boundaries)

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `lib/features/monitoring/services/reconnect_supervisor.dart` | ReconnectSupervisor class with computeBackoff + dedup + retry-forever | VERIFIED | Class exists; CR-02 immediate-mode reorder applied (lines 79-104); IN-01 dead `alertTimer` field removed. |
| `lib/features/monitoring/services/zombie_watchdog.dart` | ZombieWatchdog with 4-signal quorum | VERIFIED | CR-01 fix applied: `zombieScore` returns 0 unless PTS-stall present (line 102). Doc updated to explain the necessary-condition rationale. |
| `lib/features/monitoring/services/alert_policy.dart` | AlertPolicy with armIfAbsent / clear / cancelAll | VERIFIED | Idempotent armIfAbsent (line 31-32) preserves continuous-outage clock per D-04. |
| `lib/features/monitoring/services/connectivity_listener.dart` | Debounced connectivity + LAN/WiFi vs mobile filter | VERIFIED | WR-02 fix applied: `Connectivity().checkConnectivity()` seeds `_lastKnownHasLan` after subscribe (lines 55-69) so cellular-only startup does NOT emit phantom wifiDropped. |
| `lib/core/services/local_notifications.dart` | Channel `baby_monitor_alert` at Importance.max + fireAlert/cancelAlert | VERIFIED | Channel name (line 28), Importance.max (line 31), title 'Camera offline: ${cameraName}' (line 73), body 'No audio for 5 minutes. Tap to check.' (line 74). FSI not used (Android 14 restriction respected). |
| `lib/features/monitoring/providers/audio_player_provider.dart` | All 4 services wired with defensive try/catch | VERIFIED | 30+ wiring sites confirmed via grep: `_zombieWatchdog`, `_alertPolicy`, `_connectivityListener`, `LocalNotificationsManager.{fireAlert,cancelAlert}`. WR-01 fix at lines 397-410 (initial_open_failed handoff). WR-03 fix at lines 717-718 (`_lastAudioPts.remove(cameraId)` + `_baselineLevel.remove(cameraId)` on successful reconnect). All teardown ordering (T-04-08) preserved. |
| `lib/features/monitoring/widgets/camera_audio_card.dart` | Reconnecting render branch | VERIFIED | Status dot tertiary branch (line 142), header tint (lines 119-127), 14×14 spinner (lines 177-179), Reconnecting… text (line 187), Connecting… (line 194 — U+2026). |
| `lib/features/monitoring/screens/health_summary_screen.dart` | HealthSummaryScreen ConsumerWidget | VERIFIED | Watches healthEventsProvider + audioPlayerProvider; renders all 10 HealthEventType variants; Semantics-wrapped icons; reversed event order. |
| `lib/features/monitoring/screens/monitoring_screen.dart` | AppBar IconButton entry to HealthSummaryScreen | VERIFIED | `Icons.monitor_heart_outlined` (line 157) BEFORE `Icons.videocam` (line 166); tooltip 'Open health summary' (line 158); Navigator.push + MaterialPageRoute (lines 159-162). |
| `lib/features/monitoring/models/health_event.dart` | HealthEvent + HealthEventType (10 variants) | VERIFIED | All 10 variants (monitoringStarted/Stopped, streamStarted/Error, reconnectAttempt/Success, zombieDetected, wifiDropped/Reconnected, alertFired). |
| `lib/main.dart` | LocalNotificationsManager.init alongside ForegroundServiceManager.init | VERIFIED | Line 18 `LocalNotificationsManager.init();` after ForegroundServiceManager.init() (line 16). |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|----|--------|---------|
| audio_player_provider.dart | reconnect_supervisor.dart | `_reconnectSupervisor.requestReconnect(...)` on stream.error / stream.completed / zombie / wifi_reconnect / initial_open_failed | WIRED | 5 distinct call sites with cause string differentiation |
| audio_player_provider.dart | zombie_watchdog.dart | tick + 4 signal feeders + reset on playing | WIRED | 8 wiring sites verified (audioParams listener, buffering listener, _pollAudioLevels for PTS + bitrate, tick at end of per-camera loop, reset/resetAll on stop/dispose) |
| audio_player_provider.dart | alert_policy.dart | armIfAbsent on non-playing / clear on playing / cancelAll on teardown | WIRED | armIfAbsent ≥ 2 sites; clear ≥ 2 sites; cancelAll in stopMonitoring + onDispose |
| audio_player_provider.dart | connectivity_listener.dart | start() in startMonitoring; cancel() in stopMonitoring + onDispose | WIRED | start at line 459; cancel at lines 95, 1017 |
| audio_player_provider.dart | local_notifications.dart | fireAlert via AlertPolicy.onFire callback; cancelAlert on recovery | WIRED | callback at lines 64-79; cancelAlert at lines 228, 724 |
| zombie_watchdog onFire | reconnect_supervisor | `cause: 'zombie'` | WIRED | audio_player_provider.dart:55 |
| connectivity_listener onReconnected | reconnect_supervisor | `cause: 'wifi_reconnect', immediate: true` | WIRED | lines 766-767. After CR-02 reorder, immediate=true now actually cancels pending backoff timer (proven by supervisor.dart lines 86-87 + trigger_dedupe_test CR-02 regression). |
| monitoring_screen.dart | health_summary_screen.dart | Navigator.push + MaterialPageRoute | WIRED | line 160 |
| health_summary_screen.dart | health_events_provider.dart | ref.watch(healthEventsProvider) | WIRED | line 20 |
| main.dart | local_notifications.dart | LocalNotificationsManager.init() | WIRED | line 18 |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|---------| 
| HealthSummaryScreen | events | `ref.watch(healthEventsProvider)` → HealthEventsNotifier list | Yes — populated via `record()` from 12+ sites in audio_player_provider.dart (monitoringStarted, streamStarted, streamError, reconnectAttempt/Success, zombieDetected, wifiDropped/Reconnected, alertFired, monitoringStopped) | FLOWING |
| HealthSummaryScreen | cameras | `ref.watch(audioPlayerProvider).value.cameras` | Yes — driven by AudioPlayerNotifier per-camera state | FLOWING |
| CameraAudioCard | cs.connectionStatus reconnecting branch | propagated from supervisor onStatusChange → `_applyReconnectStatus` (line 690-705) | Yes — supervisor flips state on reconnect attempt + success | FLOWING |
| ZombieWatchdog | _ptsStallMs / _bufferingStuckMs / _bitrateZeroMs / _noAudioParamsMs | `_pollAudioLevels` polls mpv `audio-pts` + `audio-bitrate` (lines 491, 537); `player.stream.buffering`/`audioParams` listeners feed binary signals | Yes — real mpv property reads + real stream events | FLOWING |
| AlertPolicy | armed timers | `armIfAbsent` called from buffering listener + `_applyReconnectStatus` + WR-01 initial-open-failed catch | Yes — exercised by all transitions out of `playing` | FLOWING |
| ConnectivityListener | _lastKnownHasLan | `Connectivity().checkConnectivity()` snapshot + `Connectivity().onConnectivityChanged` stream | Yes (after WR-02 seed) | FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Full test suite passes | `flutter test --reporter compact` | 116/116 pass | PASS |
| Static analysis clean (no NEW issues) | `flutter analyze --no-preamble lib test` | 5 pre-existing warnings in test/features/auth + test/features/cameras (lineage predates Phase 4); 0 new | PASS |
| CR-01 regression (healthy 240-tick stream does not fire) | grep `for (var i = 0; i < 240` test/features/monitoring/zombie/quorum_test.dart | Found at line 64 | PASS |
| CR-02 regression (immediate=true cancels pending timer) | grep `'CR-02: immediate=true cancels pending retry timer'` test/features/monitoring/reconnect/trigger_dedupe_test.dart | Found at line 46 | PASS |
| WR-01 (initial_open_failed handoff) | grep `cause: 'initial_open_failed'` lib/features/monitoring/providers/audio_player_provider.dart | Found at line 405 | PASS |
| WR-02 (checkConnectivity seed) | grep `Connectivity\(\)\.checkConnectivity` lib/features/monitoring/services/connectivity_listener.dart | Found at line 55 | PASS |
| WR-03 (PTS reset on reconnect) | grep `_lastAudioPts\.remove(cameraId)` lib/features/monitoring/providers/audio_player_provider.dart | Found at line 717 | PASS |
| IN-01 (dead alertTimer removed) | grep `alertTimer` lib/features/monitoring/services/reconnect_supervisor.dart | No matches | PASS |
| LocalNotificationsManager init at boot | grep `LocalNotificationsManager.init` lib/main.dart | Found at line 18 | PASS |
| Monitor-heart icon precedes videocam in AppBar actions | grep -n in monitoring_screen.dart | line 157 < line 166 | PASS |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| RELY-01 | 04-01, 04-04 | App auto-reconnects dropped RTSP streams with exponential backoff | SATISFIED (auto) | ReconnectSupervisor + 4 D-03 trigger sites + AlertPolicy 5-min one-shot. CR-02 fix makes WiFi-back immediate-mode actually bypass backoff. WR-01 fix makes initial-open failures hand off to supervisor + alert. |
| RELY-02 | 04-01, 04-03 | App shows per-camera connection status (connecting, live, reconnecting, error) | SATISFIED (auto) | Enum extended; CameraAudioCard renders all 5 states distinguishably; widget tests pass. |
| RELY-03 | 04-02 | Stream health watchdog detects zombie streams and forces reconnect | SATISFIED (auto) | ZombieWatchdog with 4-signal quorum + CR-01 PTS-necessary fix; wired into supervisor; 9 unit tests pass including 240-tick healthy-stream guard. |
| MNTR-01 | 04-05 | App shows overnight health summary (uptime, reconnection count, stream health events) | SATISFIED (auto) | HealthSummaryScreen renders all three; AppBar entry on MonitoringScreen; 7 widget tests pass. |

No orphaned requirements — REQUIREMENTS.md maps all 4 IDs to Phase 4 and all 4 are claimed by plans 04-01..04-05 frontmatter.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| (none reintroduced post-CR fixes) | — | — | — | — |

The 04-REVIEW.md flagged 11 issues. Post-fix state in commit 0a705a3:
- **Fixed (load-bearing):** CR-01, CR-02, WR-01, WR-02, WR-03, IN-01 — verified above.
- **False alarm:** WR-04 (supervisor _perCamera teardown ordering — was already correct).
- **Deferred (not load-bearing for the goal):** WR-05 (extra fallback timer in supervisor), IN-02 (dead try/catch comment cleanup), IN-03 (more descriptive log in `_recordReconnectEvent`), IN-04 (replace `catch (_) {}` with logged catches in dispose paths). These do not affect any of the 4 success criteria; documented in 04-REVIEW.md and roadmap.

### Human Verification Required

8 items requiring on-device verification — full details in YAML frontmatter. Summary:

1. **Overnight 8h soak run** (RELY-01, RELY-03 — VALIDATION Manual-Only #1)
2. **Real WiFi flap reconnect** (RELY-01, exercises CR-02 fix — VALIDATION Manual-Only #2)
3. **Zombie recovery on real camera** (RELY-03, exercises CR-01 fix — VALIDATION Manual-Only #3)
4. **5-min push notification on real device** (RELY-01 D-04 — VALIDATION Manual-Only #4)
5. **Notification permission denied path** (RELY-01 — T-04-24 mitigation)
6. **Both-cameras-down per-camera alert separation** (RELY-01 D-04 — VALIDATION Manual-Only #6)
7. **Initial open failure end-to-end** (RELY-01 — exercises WR-01 fix)
8. **Cellular-only startup, no spurious wifiDropped** (RELY-01 — exercises WR-02 fix)

### Gaps Summary

No automated gaps found. All four ROADMAP success criteria are implementation-complete in the codebase, all post-review fixes (CR-01, CR-02, WR-01, WR-02, WR-03, IN-01) are present in commit 0a705a3 with passing regression tests, and the full 116-test suite is green with zero new analyzer warnings.

The phase cannot be marked `passed` because RELY-01 / RELY-03 / D-04 each have load-bearing manual verifications baked into VALIDATION.md (overnight Doze interaction, real AP DHCP renewal, OEM heads-up policy) that cannot be exercised in unit / widget tests. These are routine on-device checks the developer must run before final phase sign-off — they are NOT code defects.

---

_Verified: 2026-04-28T21:16:14Z_
_Verifier: Claude (gsd-verifier)_
