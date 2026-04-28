---
phase: 04-reliability-overnight-monitoring
plan: 04
status: complete
requirements: [RELY-01]
type: summary
---

# Plan 04-04 — Push Alert + WiFi Reconnect Trigger (RELY-01 closure)

## What was built

The two pieces that close out RELY-01:

1. **D-03 trigger c — WiFi reconnect**: `connectivity_plus` subscription
   wrapped by a 1-second debounced `ConnectivityListener` that emits
   edge-triggered `onDropped` / `onReconnected` callbacks. WiFi-back
   immediately retries every non-playing camera via
   `supervisor.requestReconnect(cause: 'wifi_reconnect', immediate: true)`.
2. **D-04 — 5-min one-shot alert**: extracted `AlertPolicy` class
   (per-camera `Timer` + fired flag) wired into `AudioPlayerNotifier`.
   Every transition off `playing` arms the timer; transition back to
   `playing` clears it. After 5 min continuous non-playing the policy
   fires `LocalNotificationsManager.fireAlert` and records an
   `alertFired` health event.

## Why AlertPolicy was extracted

Originally the plan suggested inline `_alertTimers` / `_alertFiredFlag`
maps on `AudioPlayerNotifier`. Testing the alert lifecycle inline would
have required spinning up the full notifier (Player, Riverpod overrides,
camera fixtures) just to advance a Timer — high-friction and brittle.

The `AlertPolicy` extraction:
- isolates the timer + flag logic behind a 4-method API (`armIfAbsent`,
  `clear`, `cancelAll`, plus `onFire` callback)
- becomes trivially fakesync-testable in 6 deterministic unit tests
- keeps the "is this camera in an outage right now" decision out of
  the supervisor (which already owns reconnect state — overlapping
  concerns there would be confusing)

The notifier owns one `AlertPolicy` instance whose `onFire` callback
glues the policy to `LocalNotificationsManager` + the health-events
notifier.

## LocalNotificationsManager init ordering

`main.dart` boot sequence:

```
1. FlutterForegroundTask.initCommunicationPort()
2. WidgetsFlutterBinding.ensureInitialized()
3. MediaKit.ensureInitialized()
4. AppLogger.instance.init()
5. ForegroundServiceManager.init()
6. LocalNotificationsManager.init()      ← NEW
7. runApp(...)
```

Steps 5 + 6 both register Android notification channels, but they target
different channels (FGS persistent vs. `baby_monitor_alert` heads-up).
Both depend on the bindings being ready (step 2). The Manager's `init()`
is idempotent (`_initialized` guard), so a second call from `fireAlert`
is a no-op — useful when the alert fires before main has finished
running on slow boots.

POST_NOTIFICATIONS permission is granted once by
`MonitoringScreen.initState` (Phase 3) and covers both channels —
RESEARCH §Section 4 confirms this is app-wide on Android 13+.

## WiFi-drop decision: record only, do NOT proactively reconnect

The plan explicitly avoids kicking the supervisor on `onDropped`.
Reasons:
- attempts against a down network fail in 5–30s and waste battery
- `player.stream.error` will fire naturally within 30–60s of network
  loss and the supervisor's existing trigger handles it
- the `wifiDropped` health event is enough for after-the-fact diagnosis
  (parents can check the health summary in the morning)

Only `onReconnected` triggers proactive retries — and only with
`immediate: true` to bypass the backoff delay (the network just came
back; waiting another 30s is pointless).

## Defensive layering (CLAUDE.md §Conventions)

Every callsite that could throw is wrapped:

| Layer | What's caught |
|-------|---------------|
| `LocalNotificationsManager.{init,fireAlert,cancelAlert}` | plugin failures, permission denials |
| `ConnectivityListener._scheduleDebounce` body | callback exceptions |
| `AlertPolicy.armIfAbsent` Timer body | `onFire` callback exceptions (logged, finally-block always cleans up the map entry) |
| `_onWifiReconnected` per-camera loop | per-call try/catch — one failed `requestReconnect` doesn't abort the rest |
| `stopMonitoring` teardown | individual try/catch around alert/connectivity/supervisor/zombie cancels — all four can fail independently |

## Key files

| File | Status | Purpose |
|------|--------|---------|
| `lib/core/services/local_notifications.dart` | created | flutter_local_notifications wrapper, `baby_monitor_alert` channel |
| `lib/features/monitoring/services/connectivity_listener.dart` | created | debounced WiFi/Ethernet edge detector |
| `lib/features/monitoring/services/alert_policy.dart` | created | per-camera one-shot Timer + flag |
| `lib/features/monitoring/providers/audio_player_provider.dart` | modified | own + wire both new services |
| `lib/main.dart` | modified | init notification channel at boot |
| `test/features/monitoring/reconnect/wifi_debounce_test.dart` | created | 7 ConnectivityListener tests |
| `test/features/monitoring/alerts/alert_timer_test.dart` | created | 6 AlertPolicy tests |

## Verification

- `flutter analyze --no-preamble lib test` → 0 new issues (5 pre-existing warnings unchanged)
- `flutter test test/features/monitoring/alerts/alert_timer_test.dart` → 6/6 pass
- `flutter test test/features/monitoring/reconnect/wifi_debounce_test.dart` → 7/7 pass
- `flutter test` → 113/113 pass (no regressions)

## Manual-only verifications (deferred to VALIDATION.md)

- Real-device overnight run: confirm alert fires within 5–10 min of
  pulling power on a camera (Doze tolerance).
- Permission denial path: deny notifications, kill app, restart, run
  monitoring, induce outage — confirm `alertFired` event still
  recorded even when notification fails to show.
- Real WiFi flap (router off → on): confirm
  `wifiDropped`/`wifiReconnected` events appear and that one
  immediate reconnect attempt fires per non-playing camera.

## Commits

- `2bf0968` — feat(04-04): LocalNotificationsManager + ConnectivityListener services (Task 1)
- `e9fa755` — feat(04-04): wire AlertPolicy + ConnectivityListener into AudioPlayerNotifier (Task 2)

## Self-Check: PASSED

All `<acceptance_criteria>` predicates from the plan satisfy. AlertPolicy
extracted as planned; both new services wired into the notifier with
defensive try/catch on every callsite; `main.dart` initializes the
notification channel at boot. RELY-01 is now fully covered: all three
D-03 reconnect triggers (player events, zombie watchdog, WiFi
reconnect) route through `ReconnectSupervisor.requestReconnect`, and
the 5-minute outage alert fires via `flutter_local_notifications` at
`Importance.max` on the `baby_monitor_alert` channel.

## Notable deviations

- **Inline execution.** Wave 3 was run inline on main rather than via
  the worktree-based gsd-executor agent. Two prior Wave 2 worktree
  runs hit a stateful Read-before-Edit hook on
  `audio_player_provider.dart` mid-execution. Since 04-04 also modifies
  that file, the orchestrator skipped the worktree to avoid a third
  blocked agent. No code differs from the plan's Step A–K — only the
  *who* changed.
