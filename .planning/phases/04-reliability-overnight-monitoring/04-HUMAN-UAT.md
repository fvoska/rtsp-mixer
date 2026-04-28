---
status: testing
phase: 04-reliability-overnight-monitoring
source: [04-VERIFICATION.md]
started: 2026-04-28T23:14:00Z
updated: 2026-04-28T23:40:00Z
---

## Current Test

number: 1
name: Overnight 8h soak run
expected: |
  App runs unattended for 8+ hours on Android with screen off; both cameras
  stay live (or recover within seconds via the supervisor); no foreground
  service death; health summary shows accurate uptime/reconnect counts in
  the morning.
awaiting: user response

## Tests

### 1. Overnight 8h soak run (RELY-01, RELY-03 — VALIDATION Manual-Only #1)
expected: App runs unattended for 8+ hours on Android with screen off; both cameras stay live (or recover within seconds via the supervisor); no FGS death; health summary shows accurate uptime/reconnect counts in the morning.
result: [pending]

### 2. Real WiFi flap reconnect (RELY-01 — exercises CR-02 fix)
expected: Toggle WiFi off and back on while monitoring is active. After the network returns, every non-playing camera reconnects within ~1 second (debounce window) without waiting through the full backoff. Health summary records `wifiDropped` then `wifiReconnected`.
result: [pending]

### 3. Zombie recovery on real camera (RELY-03 — exercises CR-01 fix)
expected: Pull power on a camera mid-stream. Within 60–90s the watchdog detects PTS-stall + corroborating signals and triggers a silent reconnect. No false-positive zombie fires during normal multi-hour operation.
result: [pending]

### 4. 5-min push notification on real device (RELY-01 D-04)
expected: Trigger a 5+ minute camera outage. Heads-up notification appears with title "Camera offline: {name}" and body "No audio for 5 minutes. Tap to check." Channel `baby_monitor_alert` at Importance.max. Tapping the notification dismisses it. No repeat notifications during the same outage.
result: [pending]

### 5. Notification permission denied path (RELY-01 — T-04-24 mitigation)
expected: Deny POST_NOTIFICATIONS at OS level. Trigger a 5+ min outage. Notification fails to appear but the `alertFired` HealthEvent IS recorded — the morning health summary shows the alert was attempted.
result: [pending]

### 6. Both-cameras-down per-camera alert separation (RELY-01 D-04)
expected: Take both cameras offline simultaneously. Both fire their own 5-min alert independently. Recovering one camera does not cancel the other's alert. Health summary shows two distinct `alertFired` events.
result: [pending]

### 7. Initial open failure end-to-end (RELY-01 — exercises WR-01 fix)
expected: Configure an unreachable RTSP URL (camera offline before monitoring starts). Camera goes to `error` state. AlertPolicy arms the 5-min timer; supervisor begins retrying with backoff. After 5 minutes the alert fires.
result: [pending]

### 8. Cellular-only startup, no spurious wifiDropped (RELY-01 — exercises WR-02 fix)
expected: Disconnect WiFi entirely (cellular-only); start the app and begin monitoring. The morning health summary contains NO `wifiDropped` event from t≈0 — the listener seeded its initial state from `Connectivity().checkConnectivity()` and recognised that LAN was never present.
result: [pending]

## Summary

total: 8
passed: 0
issues: 0
pending: 8
skipped: 0
blocked: 0

## Gaps
