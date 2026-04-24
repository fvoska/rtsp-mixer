---
phase: 04-reliability-overnight-monitoring
plan: 04
type: execute
wave: 3
depends_on: [04-01-reconnect-core-PLAN.md, 04-02-zombie-detection-PLAN.md]
files_modified:
  - lib/core/services/local_notifications.dart
  - lib/features/monitoring/services/connectivity_listener.dart
  - lib/features/monitoring/providers/audio_player_provider.dart
  - lib/main.dart
  - test/features/monitoring/alerts/alert_timer_test.dart
  - test/features/monitoring/reconnect/wifi_debounce_test.dart
autonomous: true
requirements: [RELY-01]
tags: [local-notifications, connectivity, baby-monitor, overnight, flutter, android]

must_haves:
  truths:
    - "A LocalNotificationsManager.init() is called from main() before runApp() — idempotent, creates the `baby_monitor_alert` Android channel with Importance.max"
    - "Per-camera 5-minute Timer starts when camera transitions from playing → non-playing; cancels when it returns to playing (D-04)"
    - "After 5 minutes continuous non-playing, `LocalNotificationsManager.fireAlert(cameraName)` is invoked ONCE and an `alertFired` health event is recorded"
    - "Alert is one-shot per outage cycle — flag `alertFired=true` is set on fire and reset only when the camera returns to playing (D-04)"
    - "connectivity_plus subscription fires on WiFi drop (`onConnectivityChange(false)`) and WiFi reconnect (`onConnectivityChange(true)`)"
    - "Connectivity changes are debounced with a 1-second Timer — 3 rapid flaps within 1s collapse to 1 effective transition"
    - "Mobile-only (no WiFi, no Ethernet) does NOT trigger a reconnect (per RESEARCH §Section 3 — cameras on LAN only)"
    - "On WiFi reconnected: every non-playing camera gets `requestReconnect(immediate: true)` — bypass backoff because network just came back (D-03 trigger c)"
    - "On WiFi dropped: `wifiDropped` health event recorded; on reconnect: `wifiReconnected` event recorded"
    - "Alert timer + connectivity listener cancel on stopMonitoring and onDispose"
  artifacts:
    - path: "lib/core/services/local_notifications.dart"
      provides: "LocalNotificationsManager: init() channel setup + fireAlert() + cancelAlert() via flutter_local_notifications"
      contains: "class LocalNotificationsManager"
    - path: "lib/features/monitoring/services/connectivity_listener.dart"
      provides: "ConnectivityListener: subscribes to connectivity_plus + debounces + dispatches WiFi drop/reconnect callbacks"
      contains: "class ConnectivityListener"
    - path: "lib/features/monitoring/providers/audio_player_provider.dart"
      provides: "Alert timer management (per-camera 5-min), connectivity listener wiring, alertFired/wifiDropped/wifiReconnected event recording"
      contains: "LocalNotificationsManager"
    - path: "lib/main.dart"
      provides: "Calls LocalNotificationsManager.init() alongside ForegroundServiceManager.init()"
      contains: "LocalNotificationsManager.init"
    - path: "test/features/monitoring/alerts/alert_timer_test.dart"
      provides: "fake_async tests for 5-min timer fire, cancel-on-recovery, one-shot latch"
    - path: "test/features/monitoring/reconnect/wifi_debounce_test.dart"
      provides: "fake_async + fake Stream tests for 1-second debounce + mobile-only suppression"
  key_links:
    - from: "lib/features/monitoring/providers/audio_player_provider.dart"
      to: "lib/features/monitoring/services/connectivity_listener.dart"
      via: "ConnectivityListener owned by notifier; WiFi-reconnected callback iterates cameras and calls supervisor.requestReconnect(immediate:true)"
      pattern: "ConnectivityListener"
    - from: "lib/features/monitoring/providers/audio_player_provider.dart"
      to: "lib/core/services/local_notifications.dart"
      via: "Alert timer callback invokes LocalNotificationsManager.fireAlert(cameraName); reset path calls cancelAlert"
      pattern: "LocalNotificationsManager\\.(fireAlert|cancelAlert)"
---

<objective>
Complete RELY-01 by adding the two remaining reconnect triggers and the 5-minute outage alert:

1. **D-03 trigger c — WiFi reconnect:** subscribe to `connectivity_plus.onConnectivityChanged`, debounce 1s, on WiFi-back call `supervisor.requestReconnect(cameraId, cause: 'wifi_reconnect', immediate: true)` for every non-playing camera; log `wifiDropped`/`wifiReconnected` health events.
2. **D-04 one-shot alert:** per-camera 5-minute Timer that starts on transition to non-playing and cancels on return to playing. On fire, show a local notification via `flutter_local_notifications` (channel `baby_monitor_alert`, `Importance.max`) and record an `alertFired` health event.

Purpose: Closes RELY-01 — the parent can now trust that (a) all realistic RTSP interruption modes route to the reconnect loop and (b) after 5 min of silence they are woken up.
Output: Two new service files + integration into AudioPlayerNotifier + main.dart init call + two test files. No UI/screen changes.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@CLAUDE.md
@.planning/phases/04-reliability-overnight-monitoring/04-CONTEXT.md
@.planning/phases/04-reliability-overnight-monitoring/04-RESEARCH.md
@.planning/phases/04-reliability-overnight-monitoring/04-PATTERNS.md
@.planning/phases/04-reliability-overnight-monitoring/04-UI-SPEC.md
@.planning/phases/04-reliability-overnight-monitoring/04-VALIDATION.md
@.planning/phases/04-reliability-overnight-monitoring/04-01-SUMMARY.md
@.planning/phases/04-reliability-overnight-monitoring/04-02-SUMMARY.md

<interfaces>
<!-- Stable contracts from prior plans. -->

From Plan 04-01 — AudioPlayerNotifier holds:
- `late final ReconnectSupervisor _reconnectSupervisor = ReconnectSupervisor(onAttempt: _performReconnectOpen, onStatusChange: _applyReconnectStatus, onEvent: _recordReconnectEvent);`
- `_performReconnectOpen(String cameraId)` — calls player.stop + _applyPlaybackTuning + player.open with 15s timeout
- `_findCameraName(String cameraId)` helper

From Plan 04-02 — `_zombieWatchdog` wired.

From Plan 04-01 — HealthEventType enum includes `wifiDropped, wifiReconnected, alertFired` — all three still unused.

Android permissions (AndroidManifest.xml already declares):
- `ACCESS_NETWORK_STATE` (line 6)
- `POST_NOTIFICATIONS` (line 7)
- No change required. `flutter_local_notifications` ^19.0.0 uses POST_NOTIFICATIONS which is already granted via `FlutterForegroundTask.requestNotificationPermission()` in MonitoringScreen.initState (RESEARCH §Section 4 — "same permission covers both").

From lib/core/services/foreground_service.dart — analog shape for LocalNotificationsManager:
- static class with `static bool _initialized = false;` idempotent init
- all entry points log via `appLog('FGS', ...)` — new tag for alerts is `NOTIF`

From connectivity_plus docs (RESEARCH §Section 3):
```dart
StreamSubscription<List<ConnectivityResult>> sub =
    Connectivity().onConnectivityChanged.listen((results) {...});
// results contains ConnectivityResult.wifi, .mobile, .ethernet, .none
```

From flutter_local_notifications docs (RESEARCH §Section 4):
```dart
const AndroidNotificationChannel channel = AndroidNotificationChannel(
  'baby_monitor_alert',
  'Camera Offline Alerts',
  description: 'Fires when a camera has been offline for 5 minutes',
  importance: Importance.max,
  playSound: true,
  enableVibration: true,
);

await _plugin
    .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
    ?.createNotificationChannel(channel);

const details = AndroidNotificationDetails(
  'baby_monitor_alert',
  'Camera Offline Alerts',
  importance: Importance.max,
  priority: Priority.high,
  category: AndroidNotificationCategory.alarm,
);
await _plugin.show(cameraIdHash, title, body, const NotificationDetails(android: details));
```

UI-SPEC §Copywriting Contract (alert copy — locked):
- Channel name: `Camera Offline Alerts`
- Channel description: `Fires when a camera has been offline for 5 minutes`
- Title: `Camera offline: {cameraName}`
- Body: `No audio for 5 minutes. Tap to check.`
- Ticker: `Camera offline`
</interfaces>
</context>

<tasks>

<task type="auto" tdd="true">
  <name>Task 1: LocalNotificationsManager + ConnectivityListener services (isolated, unit-tested)</name>
  <files>
    lib/core/services/local_notifications.dart,
    lib/features/monitoring/services/connectivity_listener.dart,
    test/features/monitoring/reconnect/wifi_debounce_test.dart
  </files>
  <read_first>
    - .planning/phases/04-reliability-overnight-monitoring/04-PATTERNS.md §6 (ConnectivityListener — debounce pattern, _subscriptions integration), §7 (LocalNotificationsManager — idempotent init, appLog on entry, fire/cancel), §Shared Patterns (Defensive Error Handling)
    - .planning/phases/04-reliability-overnight-monitoring/04-RESEARCH.md §Section 3 (connectivity_plus subscription + debounce + mobile/wifi distinction), §Section 4 (flutter_local_notifications channel setup + fire + POST_NOTIFICATIONS permission), §Pitfall 2 (Doze note — plain Timer assumed sufficient given Phase 3 battery-opt exemption), §Pitfall 4 (WifiLock does not suppress toggles)
    - .planning/phases/04-reliability-overnight-monitoring/04-CONTEXT.md §decisions D-03 (triggers c — WiFi reconnect), D-04 (5-min one-shot, per-camera)
    - .planning/phases/04-reliability-overnight-monitoring/04-UI-SPEC.md §Copywriting Contract > 5-minute disconnection alert (exact copy strings)
    - CLAUDE.md §Conventions > Defensive error handling
    - lib/core/services/foreground_service.dart (shape analog for LocalNotificationsManager)
    - Connectivity plus docs — use `mcp__context7__*` or `npx ctx7 library connectivity_plus` to confirm API surface for `onConnectivityChanged` returning `Stream<List<ConnectivityResult>>`
  </read_first>
  <behavior>
    - Test (wifi_debounce_test.dart) 1: three rapid connectivity events within 500ms result in exactly ONE effective dispatch (debounce collapses them).
    - Test 2: transition `[wifi]` → `[none]` (after debounce) invokes `onDropped` exactly once.
    - Test 3: transition `[none]` → `[wifi]` (after debounce) invokes `onReconnected` exactly once.
    - Test 4: `[none]` → `[mobile]` does NOT invoke `onReconnected` — only WiFi or Ethernet counts as "LAN reachable".
    - Test 5: `[wifi]` → `[wifi]` (no transition) does not invoke either callback.
    - Test 6: `cancel()` tears down the debounce timer and the subscription — no further callbacks fire.
    - LocalNotificationsManager has no unit test in this task (it's a thin wrapper around a plugin that doesn't have a test mode without custom mocks) — its correctness is verified by grep on the action steps and by the overnight manual verification item in VALIDATION.md.
  </behavior>
  <action>
    Step A — Create lib/core/services/local_notifications.dart (per PATTERNS.md §7 + RESEARCH §Section 4 + UI-SPEC alert copy):

    ```dart
    import 'package:flutter_local_notifications/flutter_local_notifications.dart';

    import '../logging/app_logger.dart';

    /// Manages the 5-minute camera-offline alert channel (D-04).
    /// - Idempotent init (mirrors ForegroundServiceManager pattern)
    /// - Uses `baby_monitor_alert` channel at Importance.max for heads-up display
    /// - Skips full-screen intent (Android 14 restricts FSI to calling/alarm apps)
    /// - POST_NOTIFICATIONS permission is already granted by MonitoringScreen.initState
    ///   (covers both FGS and alert channels — app-wide grant)
    class LocalNotificationsManager {
      LocalNotificationsManager._();

      static final FlutterLocalNotificationsPlugin _plugin =
          FlutterLocalNotificationsPlugin();
      static bool _initialized = false;

      /// Register the Android channel + plugin. Safe to call multiple times.
      /// Call from main() alongside ForegroundServiceManager.init().
      static Future<void> init() async {
        if (_initialized) return;
        const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
        await _plugin.initialize(
          const InitializationSettings(android: androidInit),
        );
        const channel = AndroidNotificationChannel(
          'baby_monitor_alert',
          'Camera Offline Alerts',
          description: 'Fires when a camera has been offline for 5 minutes',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
          enableLights: true,
        );
        await _plugin
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
            ?.createNotificationChannel(channel);
        _initialized = true;
        appLog('NOTIF', 'LocalNotificationsManager initialized (channel=baby_monitor_alert)');
      }

      /// Fire a heads-up notification for one camera (D-04).
      /// Notification ID is derived from cameraId.hashCode — subsequent
      /// fires for the same camera overwrite the previous notification.
      static Future<void> fireAlert({
        required String cameraId,
        required String cameraName,
      }) async {
        try {
          await init();
          appLog('NOTIF', 'Fire alert for $cameraName ($cameraId)');
          const details = AndroidNotificationDetails(
            'baby_monitor_alert',
            'Camera Offline Alerts',
            channelDescription: 'Fires when a camera has been offline for 5 minutes',
            importance: Importance.max,
            priority: Priority.high,
            category: AndroidNotificationCategory.alarm,
            autoCancel: true,
            ongoing: false,
            ticker: 'Camera offline',
          );
          await _plugin.show(
            cameraId.hashCode,
            'Camera offline: $cameraName',
            'No audio for 5 minutes. Tap to check.',
            const NotificationDetails(android: details),
          );
        } catch (e) {
          // Defensive: never let notification failures kill the monitoring loop.
          appLog('NOTIF', 'fireAlert failed for $cameraName: $e');
        }
      }

      /// Dismiss a previously-fired alert (called if camera recovers fast enough
      /// that the user hasn't dismissed the notification themselves).
      static Future<void> cancelAlert(String cameraId) async {
        try {
          appLog('NOTIF', 'Cancel alert for $cameraId');
          await _plugin.cancel(cameraId.hashCode);
        } catch (e) {
          appLog('NOTIF', 'cancelAlert failed for $cameraId: $e');
        }
      }
    }
    ```

    Step B — Create lib/features/monitoring/services/connectivity_listener.dart (per PATTERNS.md §6 + RESEARCH §Section 3):

    ```dart
    import 'dart:async';

    import 'package:connectivity_plus/connectivity_plus.dart';

    import '../../../core/logging/app_logger.dart';

    /// Wraps connectivity_plus with a 1-second debounce + WiFi/Ethernet vs mobile logic.
    /// Emits edge-triggered callbacks:
    ///   - onDropped: LAN reachability lost (was on, now off)
    ///   - onReconnected: LAN reachability restored (was off, now on)
    ///
    /// Rationale (RESEARCH §Section 3):
    ///   - connectivity_plus docs: "doesn't filter events, nor ensures distinct values" — so rapid flaps can fire 3–5 events. Debounce to avoid thundering-herd reconnects.
    ///   - Cameras are on LAN. Mobile-only is useless for reaching them — suppress those edges.
    class ConnectivityListener {
      ConnectivityListener({
        required this.onDropped,
        required this.onReconnected,
        this.debounce = const Duration(seconds: 1),
        Stream<List<ConnectivityResult>>? stream,
      }) : _stream = stream ?? Connectivity().onConnectivityChanged;

      final void Function() onDropped;
      final void Function() onReconnected;
      final Duration debounce;
      final Stream<List<ConnectivityResult>> _stream;

      StreamSubscription<List<ConnectivityResult>>? _sub;
      Timer? _debounceTimer;
      bool? _lastKnownHasLan; // null = never evaluated

      /// Start listening. Must pair with cancel().
      void start() {
        _sub?.cancel();
        _sub = _stream.listen((results) {
          try {
            final hasWifi = results.contains(ConnectivityResult.wifi);
            final hasEthernet = results.contains(ConnectivityResult.ethernet);
            final lanReachable = hasWifi || hasEthernet;
            _scheduleDebounce(lanReachable);
          } catch (e) {
            appLog('CONN', 'Listener error (non-fatal): $e');
          }
        });
        appLog('CONN', 'ConnectivityListener started (debounce=${debounce.inMilliseconds}ms)');
      }

      void _scheduleDebounce(bool lanReachable) {
        _debounceTimer?.cancel();
        _debounceTimer = Timer(debounce, () {
          try {
            if (_lastKnownHasLan == lanReachable) return;
            final wasOn = _lastKnownHasLan ?? true;
            _lastKnownHasLan = lanReachable;
            if (!lanReachable && wasOn) {
              appLog('CONN', 'LAN dropped');
              onDropped();
            } else if (lanReachable && !wasOn) {
              appLog('CONN', 'LAN reconnected');
              onReconnected();
            }
          } catch (e) {
            appLog('CONN', 'Debounce callback crashed: $e');
          }
        });
      }

      /// Cancel the subscription + any pending debounce timer.
      void cancel() {
        _debounceTimer?.cancel();
        _debounceTimer = null;
        _sub?.cancel();
        _sub = null;
        appLog('CONN', 'ConnectivityListener cancelled');
      }
    }
    ```

    Step C — Create test/features/monitoring/reconnect/wifi_debounce_test.dart:

    ```dart
    import 'dart:async';

    import 'package:connectivity_plus/connectivity_plus.dart';
    import 'package:fake_async/fake_async.dart';
    import 'package:flutter_test/flutter_test.dart';
    import 'package:rtsp_mixer/features/monitoring/services/connectivity_listener.dart';

    void main() {
      group('ConnectivityListener (D-03 trigger c + RESEARCH §Section 3)', () {
        late StreamController<List<ConnectivityResult>> controller;
        late int dropped;
        late int reconnected;
        late ConnectivityListener listener;

        setUp(() {
          controller = StreamController<List<ConnectivityResult>>.broadcast();
          dropped = 0;
          reconnected = 0;
          listener = ConnectivityListener(
            stream: controller.stream,
            onDropped: () => dropped++,
            onReconnected: () => reconnected++,
          );
        });

        tearDown(() async {
          listener.cancel();
          await controller.close();
        });

        test('three rapid flaps within 500ms collapse to one effective transition', () {
          fakeAsync((async) {
            listener.start();
            // Baseline: "wifi" (listener's _lastKnownHasLan defaults to null, wasOn=true)
            controller.add([ConnectivityResult.wifi]);
            async.elapse(const Duration(milliseconds: 100));
            controller.add([ConnectivityResult.none]);
            async.elapse(const Duration(milliseconds: 100));
            controller.add([ConnectivityResult.wifi]);
            async.elapse(const Duration(milliseconds: 100));
            controller.add([ConnectivityResult.none]);
            // debounce fires 1s after last event
            async.elapse(const Duration(milliseconds: 1100));
            expect(dropped, 1);
            expect(reconnected, 0);
          });
        });

        test('[wifi] -> [none] triggers onDropped once after debounce', () {
          fakeAsync((async) {
            listener.start();
            controller.add([ConnectivityResult.wifi]);
            async.elapse(const Duration(milliseconds: 1100));
            controller.add([ConnectivityResult.none]);
            async.elapse(const Duration(milliseconds: 1100));
            expect(dropped, 1);
          });
        });

        test('[none] -> [wifi] triggers onReconnected once after debounce', () {
          fakeAsync((async) {
            listener.start();
            controller.add([ConnectivityResult.none]);
            async.elapse(const Duration(milliseconds: 1100));
            controller.add([ConnectivityResult.wifi]);
            async.elapse(const Duration(milliseconds: 1100));
            expect(reconnected, 1);
          });
        });

        test('[none] -> [mobile] does NOT trigger onReconnected (mobile != LAN)', () {
          fakeAsync((async) {
            listener.start();
            controller.add([ConnectivityResult.none]);
            async.elapse(const Duration(milliseconds: 1100));
            controller.add([ConnectivityResult.mobile]);
            async.elapse(const Duration(milliseconds: 1100));
            expect(reconnected, 0);
          });
        });

        test('[wifi] -> [wifi] is a no-op', () {
          fakeAsync((async) {
            listener.start();
            controller.add([ConnectivityResult.wifi]);
            async.elapse(const Duration(milliseconds: 1100));
            controller.add([ConnectivityResult.wifi]);
            async.elapse(const Duration(milliseconds: 1100));
            expect(dropped, 0);
            expect(reconnected, 0);
          });
        });

        test('ethernet counts as LAN (macOS dev builds)', () {
          fakeAsync((async) {
            listener.start();
            controller.add([ConnectivityResult.none]);
            async.elapse(const Duration(milliseconds: 1100));
            controller.add([ConnectivityResult.ethernet]);
            async.elapse(const Duration(milliseconds: 1100));
            expect(reconnected, 1);
          });
        });

        test('cancel() stops delivery — no callbacks after cancel', () {
          fakeAsync((async) {
            listener.start();
            controller.add([ConnectivityResult.wifi]);
            async.elapse(const Duration(milliseconds: 1100));
            listener.cancel();
            controller.add([ConnectivityResult.none]);
            async.elapse(const Duration(milliseconds: 2000));
            expect(dropped, 0);
            expect(reconnected, 0);
          });
        });
      });
    }
    ```

    Step D — Verify:
      Run `flutter pub get` (if not already done in Plan 04-01 — connectivity_plus must resolve).
      Run `flutter analyze --no-preamble lib test` — zero issues.
      Run `flutter test test/features/monitoring/reconnect/wifi_debounce_test.dart` — all 7 tests green.
  </action>
  <verify>
    <automated>flutter analyze --no-preamble lib test &amp;&amp; flutter test --reporter expanded test/features/monitoring/reconnect/wifi_debounce_test.dart</automated>
  </verify>
  <acceptance_criteria>
    - `test -f lib/core/services/local_notifications.dart` exits 0
    - `grep "class LocalNotificationsManager" lib/core/services/local_notifications.dart` exits 0
    - `grep "'baby_monitor_alert'" lib/core/services/local_notifications.dart` exits 0
    - `grep "'Camera Offline Alerts'" lib/core/services/local_notifications.dart` exits 0
    - `grep "Importance.max" lib/core/services/local_notifications.dart` exits 0
    - `grep "'Camera offline: \$cameraName'" lib/core/services/local_notifications.dart` exits 0
    - `grep "'No audio for 5 minutes. Tap to check.'" lib/core/services/local_notifications.dart` exits 0
    - `grep "fullScreenIntent" lib/core/services/local_notifications.dart` exits 1 (FSI NOT used per RESEARCH §Section 4 / Android 14 restriction)
    - `test -f lib/features/monitoring/services/connectivity_listener.dart` exits 0
    - `grep "class ConnectivityListener" lib/features/monitoring/services/connectivity_listener.dart` exits 0
    - `grep "Timer\\?\\s*_debounceTimer" lib/features/monitoring/services/connectivity_listener.dart` exits 0
    - `grep "ConnectivityResult.wifi\\|ConnectivityResult.ethernet" lib/features/monitoring/services/connectivity_listener.dart` shows both
    - `grep "ConnectivityResult.mobile" lib/features/monitoring/services/connectivity_listener.dart` exits 1 (mobile is NOT treated as LAN — implicitly excluded by `hasWifi || hasEthernet` check)
    - `flutter test test/features/monitoring/reconnect/wifi_debounce_test.dart` reports 7 tests passed
    - `flutter analyze --no-preamble lib test` exits 0
  </acceptance_criteria>
  <done>
    Two new services exist in isolation: LocalNotificationsManager (channel + fire/cancel) and ConnectivityListener (debounced WiFi/Ethernet stream). Connectivity listener is unit-tested; notification manager is verified by grep + overnight manual test (VALIDATION.md).
  </done>
</task>

<task type="auto" tdd="true">
  <name>Task 2: Wire alert timer + connectivity listener into AudioPlayerNotifier; call LocalNotificationsManager.init in main()</name>
  <files>
    lib/features/monitoring/providers/audio_player_provider.dart,
    lib/main.dart,
    test/features/monitoring/alerts/alert_timer_test.dart
  </files>
  <read_first>
    - .planning/phases/04-reliability-overnight-monitoring/04-PATTERNS.md §4 (ReconnectSupervisor's _ReconnectState already has alertTimer and alertFired fields — repurpose OR create new notifier-level maps), §8 (startMonitoring + stopMonitoring extension sites)
    - .planning/phases/04-reliability-overnight-monitoring/04-RESEARCH.md §Section 5 (alert timer lives with per-camera state), §Pitfall 6 (user denies notification permission — fallback is still to record alertFired event)
    - .planning/phases/04-reliability-overnight-monitoring/04-CONTEXT.md §decisions D-04 (per-camera, 5-min continuous non-playing, one-shot per cycle, reset on playing)
    - CLAUDE.md §Conventions > Defensive error handling
    - lib/features/monitoring/providers/audio_player_provider.dart (ENTIRE FILE — post-04-02; must understand _applyReconnectStatus, _listenToPlayer, stopMonitoring teardown order)
    - lib/features/monitoring/services/reconnect_supervisor.dart (supervisor API — requestReconnect supports `immediate: true` for WiFi-back trigger)
    - lib/main.dart (current 18-line file; see existing ForegroundServiceManager.init() invocation)
  </read_first>
  <behavior>
    - Alert timer is a NEW Map<String, Timer?> on AudioPlayerNotifier (`_alertTimers`) + a Map<String, bool> (`_alertFiredFlag`). These are separate from ReconnectSupervisor's internal per-camera state (which may be cleared by supervisor.cancelAll during teardown).
    - When camera transitions from `playing` → any other state (error / reconnecting / connecting / idle): start a 5-minute Timer for that camera. If a Timer is already running, leave it alone (D-04 "continuous non-playing" — do not reset the clock on status flaps within the outage).
    - When camera transitions to `playing`: cancel the Timer, set `_alertFiredFlag[cameraId] = false`, and call `LocalNotificationsManager.cancelAlert(cameraId)` to dismiss any already-fired notification.
    - When the Timer fires: if `_alertFiredFlag[cameraId]` is false, call `LocalNotificationsManager.fireAlert(...)`, set the flag to true, record an `alertFired` health event.
    - ConnectivityListener wiring: constructed in the AudioPlayerNotifier field init; `start()` called at the end of `startMonitoring`; `cancel()` called in `stopMonitoring` and `onDispose`.
    - WiFi dropped callback: record a `wifiDropped` health event (no reconnect kickoff — reconnect attempts against a down network waste battery; supervisor will already be retrying because player.stream.error fires shortly after).
    - WiFi reconnected callback: record `wifiReconnected` event, then iterate `state.value.cameras` and for every camera whose connectionStatus != `playing`, call `_reconnectSupervisor.requestReconnect(cameraId, cause: 'wifi_reconnect', immediate: true)`.
    - On stopMonitoring: cancel every entry in `_alertTimers`, clear the map, clear `_alertFiredFlag`. Cancel the connectivity listener. Dismiss any alert notifications for known cameras (idempotent cancelAlert calls).
    - Alert tests use fake_async to advance 5 minutes and verify:
      (a) fire exactly once after 5 min non-playing
      (b) cancel-on-playing removes the pending fire
      (c) one-shot — a second Timer expiry within the same outage does not fire again (the flag prevents it; though in practice the Timer is cancelled on first fire, we test the flag as a defense-in-depth)
      (d) return-to-playing resets the flag so the NEXT outage can fire again
  </behavior>
  <action>
    Step A — Add imports to audio_player_provider.dart:
    ```dart
    import '../../../core/services/local_notifications.dart';
    import '../services/connectivity_listener.dart';
    ```

    Step B — Add alert + connectivity state to AudioPlayerNotifier (near other fields):
    ```dart
    // D-04: per-camera alert timer + one-shot latch (in-memory, session-scoped).
    final Map<String, Timer> _alertTimers = {};
    final Map<String, bool> _alertFiredFlag = {};
    static const _alertThreshold = Duration(minutes: 5);

    // D-03 trigger c: WiFi reconnect listener.
    late final ConnectivityListener _connectivityListener = ConnectivityListener(
      onDropped: _onWifiDropped,
      onReconnected: _onWifiReconnected,
    );
    ```

    Step C — Add the three new private methods near `_applyReconnectStatus`:

    ```dart
    /// D-04: ensure an alert Timer is running for a camera transitioning to non-playing.
    /// Idempotent — if a Timer is already scheduled, do not reset it (continuous-outage clock).
    void _ensureAlertTimer(String cameraId, String cameraName) {
      if (_alertTimers.containsKey(cameraId)) return;
      appLog('NOTIF', 'Starting 5-min alert timer for $cameraName');
      _alertTimers[cameraId] = Timer(_alertThreshold, () {
        try {
          if (_alertFiredFlag[cameraId] == true) {
            appLog('NOTIF', '$cameraName: alert already fired this cycle — skipping');
            return;
          }
          _alertFiredFlag[cameraId] = true;
          LocalNotificationsManager.fireAlert(
            cameraId: cameraId,
            cameraName: cameraName,
          );
          try {
            ref.read(healthEventsProvider.notifier).record(HealthEvent(
                  timestamp: DateTime.now(),
                  type: HealthEventType.alertFired,
                  cameraId: cameraId,
                  cameraName: cameraName,
                ));
          } catch (e) {
            appLog('NOTIF', 'Failed to record alertFired event: $e');
          }
        } catch (e) {
          appLog('NOTIF', '$cameraName: alert timer callback crashed: $e');
        } finally {
          _alertTimers.remove(cameraId);
        }
      });
    }

    /// D-04: cancel pending alert + reset one-shot flag when camera recovers.
    void _clearAlert(String cameraId) {
      final t = _alertTimers.remove(cameraId);
      t?.cancel();
      _alertFiredFlag[cameraId] = false;
      LocalNotificationsManager.cancelAlert(cameraId);
    }

    /// D-03 trigger c: WiFi dropped — record event only; supervisor will pick up
    /// player.stream.error within 30–60s naturally. Do NOT proactively reconnect
    /// while network is down — attempts would fail and waste battery.
    void _onWifiDropped() {
      appLog('CONN', 'WiFi dropped — recording event');
      try {
        ref.read(healthEventsProvider.notifier).record(HealthEvent(
              timestamp: DateTime.now(),
              type: HealthEventType.wifiDropped,
            ));
      } catch (e) {
        appLog('CONN', 'Failed to record wifiDropped: $e');
      }
    }

    /// D-03 trigger c: WiFi reconnected — immediate retry for any non-playing camera.
    /// Bypasses backoff because network just came back.
    void _onWifiReconnected() {
      appLog('CONN', 'WiFi reconnected — triggering immediate reconnect for non-playing cameras');
      try {
        ref.read(healthEventsProvider.notifier).record(HealthEvent(
              timestamp: DateTime.now(),
              type: HealthEventType.wifiReconnected,
            ));
      } catch (e) {
        appLog('CONN', 'Failed to record wifiReconnected: $e');
      }
      final current = state.value;
      if (current == null) return;
      for (final cam in current.cameras) {
        if (cam.connectionStatus != CameraConnectionStatus.playing) {
          _reconnectSupervisor.requestReconnect(
            cam.cameraId,
            cause: 'wifi_reconnect',
            immediate: true,
          );
        }
      }
    }
    ```

    Step D — Hook alert-timer lifecycle into `_applyReconnectStatus` (added in Plan 04-01 and extended in Plan 04-02). At the end of the existing method, AFTER the zombie reset block, add:

    ```dart
    // D-04 alert-timer lifecycle on supervisor-driven status transitions.
    final cameraName = _findCameraName(cameraId) ?? cameraId;
    if (status == ReconnectStatus.playing) {
      _clearAlert(cameraId);
    } else {
      _ensureAlertTimer(cameraId, cameraName);
    }
    ```

    Step E — Hook alert-timer lifecycle into `player.stream.buffering` listener (lines ~105–122). The existing listener flips status between `playing` and `connecting` on buffering changes. After the existing state transition logic AND the zombie buffering-feed extension from Plan 04-02, add:

    ```dart
    // D-04: if buffering forced us off `playing`, start the outage clock.
    if (buffering) {
      _ensureAlertTimer(cameraId, cameraName);
    }
    ```

    Note: transition back to `playing` via the non-buffering branch is already covered by `_applyReconnectStatus` when supervisor flips state. The direct buffering=false path in the existing listener should ALSO call `_clearAlert(cameraId)` when the camera returns to playing. Add at the end of the `buffering=false` branch (line ~118, inside the `else if` that flips to playing):

    ```dart
    _clearAlert(cameraId);
    ```

    Step F — In `startMonitoring`, near the existing notification text update (around line 303 after `ForegroundServiceManager.updateNotification`), add:
    ```dart
    _connectivityListener.start();
    ```

    Also, at the end of the per-camera try block where `camState = camState.copyWith(playing)` is set (line ~257), add an alert-clear to handle the edge case where a camera was previously in an outage and is now recovering on restart:
    ```dart
    _clearAlert(camera.id);
    ```

    Step G — In `stopMonitoring` (BEFORE `_reconnectSupervisor.cancelAll()` added in Plan 04-01 — order: cancel alerts first, then supervisor, then zombie, then subscriptions), insert:
    ```dart
    for (final t in _alertTimers.values) { t.cancel(); }
    _alertTimers.clear();
    for (final id in _alertFiredFlag.keys.toList()) {
      LocalNotificationsManager.cancelAlert(id);
    }
    _alertFiredFlag.clear();
    _connectivityListener.cancel();
    ```

    Step H — Extend `ref.onDispose` (lines ~31–44). Alongside the supervisor + zombie teardowns already added in prior plans:
    ```dart
    for (final t in _alertTimers.values) { t.cancel(); }
    _alertTimers.clear();
    _alertFiredFlag.clear();
    try { _connectivityListener.cancel(); } catch (_) {}
    ```

    Step I — Update lib/main.dart to call LocalNotificationsManager.init() alongside the existing ForegroundServiceManager.init(). After line 15 (`ForegroundServiceManager.init();`), add:
    ```dart
    // ignore: unawaited_futures
    LocalNotificationsManager.init();
    ```

    Also add the import at the top:
    ```dart
    import 'core/services/local_notifications.dart';
    ```

    Step J — Create test/features/monitoring/alerts/alert_timer_test.dart. Since the actual alert lifecycle sits inside AudioPlayerNotifier (which requires a live Player + Riverpod container with many overrides), this test validates the alert-timer BEHAVIOR via a lightweight reproduction using a plain AlertTimerPolicy helper. Factor the alert policy into a small testable unit:

    First, introduce a tiny helper inside `audio_player_provider.dart` (OR extract to a private `_AlertPolicy` class that can be tested — simplest path is a standalone extractable piece). For testability, create a small extracted class that encapsulates the timer + one-shot flag logic:

    Create (as part of Step C already done — no new file needed) and test the behaviors by using `fake_async` against the notifier's internals. However, direct notifier testing is heavy.

    Simpler choice: extract the policy into a standalone class `_AlertPolicy` inside `audio_player_provider.dart` (or a dedicated file) and test THAT. Do the following:

    Create lib/features/monitoring/services/alert_policy.dart:

    ```dart
    import 'dart:async';

    import '../../../core/logging/app_logger.dart';

    /// D-04 one-shot alert policy. Owns per-camera Timer + fired flag.
    /// Extracted from AudioPlayerNotifier for unit-testability.
    class AlertPolicy {
      AlertPolicy({
        required this.onFire,
        this.threshold = const Duration(minutes: 5),
      });

      /// Invoked exactly once per outage cycle, after `threshold` of continuous non-playing.
      final void Function(String cameraId) onFire;
      final Duration threshold;

      final Map<String, Timer> _timers = {};
      final Map<String, bool> _fired = {};

      /// Called when a camera enters a non-playing state. Idempotent —
      /// does not reset the clock if a timer is already pending.
      void armIfAbsent(String cameraId) {
        if (_timers.containsKey(cameraId)) return;
        _timers[cameraId] = Timer(threshold, () {
          try {
            if (_fired[cameraId] == true) return;
            _fired[cameraId] = true;
            onFire(cameraId);
          } catch (e) {
            appLog('NOTIF', 'AlertPolicy onFire crashed: $e');
          } finally {
            _timers.remove(cameraId);
          }
        });
      }

      /// Called when a camera returns to playing. Cancels pending Timer,
      /// resets the fired flag so a subsequent outage can fire again.
      void clear(String cameraId) {
        _timers.remove(cameraId)?.cancel();
        _fired[cameraId] = false;
      }

      /// Teardown — cancels all pending Timers. Call on stopMonitoring.
      void cancelAll() {
        for (final t in _timers.values) { t.cancel(); }
        _timers.clear();
        _fired.clear();
      }

      /// Test hook.
      bool isArmed(String cameraId) => _timers.containsKey(cameraId);
      bool hasFired(String cameraId) => _fired[cameraId] ?? false;
    }
    ```

    THEN modify audio_player_provider.dart Step C's approach: replace the inline `_alertTimers` / `_alertFiredFlag` fields + `_ensureAlertTimer` / `_clearAlert` methods with an AlertPolicy instance:

    ```dart
    late final AlertPolicy _alertPolicy = AlertPolicy(
      onFire: (cameraId) {
        final cameraName = _findCameraName(cameraId) ?? cameraId;
        LocalNotificationsManager.fireAlert(
          cameraId: cameraId,
          cameraName: cameraName,
        );
        try {
          ref.read(healthEventsProvider.notifier).record(HealthEvent(
                timestamp: DateTime.now(),
                type: HealthEventType.alertFired,
                cameraId: cameraId,
                cameraName: cameraName,
              ));
        } catch (e) {
          appLog('NOTIF', 'Failed to record alertFired event: $e');
        }
      },
    );
    ```

    Replace `_ensureAlertTimer(cameraId, cameraName)` call sites with `_alertPolicy.armIfAbsent(cameraId)`. Replace `_clearAlert(cameraId)` call sites with:
    ```dart
    _alertPolicy.clear(cameraId);
    LocalNotificationsManager.cancelAlert(cameraId);
    ```

    In stopMonitoring: `_alertPolicy.cancelAll()` plus cancelAlert loop. In onDispose: `_alertPolicy.cancelAll()`.

    Then the test file:

    ```dart
    import 'package:fake_async/fake_async.dart';
    import 'package:flutter_test/flutter_test.dart';
    import 'package:rtsp_mixer/features/monitoring/services/alert_policy.dart';

    void main() {
      group('AlertPolicy (D-04: 5-min one-shot per camera)', () {
        test('fires exactly once after 5 minutes of continuous non-playing', () {
          fakeAsync((async) {
            final fired = <String>[];
            final policy = AlertPolicy(onFire: fired.add);
            policy.armIfAbsent('cam1');
            async.elapse(const Duration(minutes: 4, seconds: 59));
            expect(fired, isEmpty);
            async.elapse(const Duration(seconds: 2));
            expect(fired, ['cam1']);
            expect(policy.hasFired('cam1'), true);
            expect(policy.isArmed('cam1'), false);
          });
        });

        test('clear() cancels pending Timer before fire', () {
          fakeAsync((async) {
            final fired = <String>[];
            final policy = AlertPolicy(onFire: fired.add);
            policy.armIfAbsent('cam1');
            async.elapse(const Duration(minutes: 2));
            policy.clear('cam1');
            async.elapse(const Duration(minutes: 10));
            expect(fired, isEmpty);
            expect(policy.hasFired('cam1'), false);
          });
        });

        test('armIfAbsent during active timer does NOT reset the clock', () {
          fakeAsync((async) {
            final fired = <String>[];
            final policy = AlertPolicy(onFire: fired.add);
            policy.armIfAbsent('cam1');
            async.elapse(const Duration(minutes: 4));
            policy.armIfAbsent('cam1'); // no-op
            async.elapse(const Duration(seconds: 61));
            expect(fired, ['cam1']);
          });
        });

        test('return-to-playing resets flag — next outage can fire again', () {
          fakeAsync((async) {
            final fired = <String>[];
            final policy = AlertPolicy(onFire: fired.add);
            // First outage: fire
            policy.armIfAbsent('cam1');
            async.elapse(const Duration(minutes: 5, seconds: 1));
            expect(fired, ['cam1']);
            // Recovery
            policy.clear('cam1');
            // Second outage
            policy.armIfAbsent('cam1');
            async.elapse(const Duration(minutes: 5, seconds: 1));
            expect(fired, ['cam1', 'cam1']);
          });
        });

        test('per-camera independence — two outages fire two separate events', () {
          fakeAsync((async) {
            final fired = <String>[];
            final policy = AlertPolicy(onFire: fired.add);
            policy.armIfAbsent('cam1');
            async.elapse(const Duration(minutes: 2));
            policy.armIfAbsent('cam2');
            async.elapse(const Duration(minutes: 3, seconds: 1));
            expect(fired, ['cam1']);           // cam1 at T+5:01
            async.elapse(const Duration(minutes: 2, seconds: 1));
            expect(fired, ['cam1', 'cam2']);  // cam2 at T+7:02 (2min after cam1)
          });
        });

        test('cancelAll() tears down all pending Timers and flags', () {
          fakeAsync((async) {
            final fired = <String>[];
            final policy = AlertPolicy(onFire: fired.add);
            policy.armIfAbsent('cam1');
            policy.armIfAbsent('cam2');
            async.elapse(const Duration(minutes: 3));
            policy.cancelAll();
            async.elapse(const Duration(minutes: 10));
            expect(fired, isEmpty);
            expect(policy.isArmed('cam1'), false);
            expect(policy.isArmed('cam2'), false);
          });
        });
      });
    }
    ```

    Step K — Verify:
      Run `flutter analyze --no-preamble lib test` — zero issues.
      Run `flutter test test/features/monitoring/alerts/alert_timer_test.dart` — all 6 tests green.
      Run `flutter test` — full suite green.
  </action>
  <verify>
    <automated>flutter analyze --no-preamble lib test &amp;&amp; flutter test --reporter expanded test/features/monitoring/alerts/alert_timer_test.dart test/features/monitoring/reconnect/wifi_debounce_test.dart</automated>
  </verify>
  <acceptance_criteria>
    - `test -f lib/features/monitoring/services/alert_policy.dart` exits 0
    - `grep "class AlertPolicy" lib/features/monitoring/services/alert_policy.dart` exits 0
    - `grep "threshold = const Duration(minutes: 5)" lib/features/monitoring/services/alert_policy.dart` exits 0
    - `grep "_alertPolicy = AlertPolicy" lib/features/monitoring/providers/audio_player_provider.dart` exits 0
    - `grep "_connectivityListener = ConnectivityListener" lib/features/monitoring/providers/audio_player_provider.dart` exits 0
    - `grep "_alertPolicy.armIfAbsent" lib/features/monitoring/providers/audio_player_provider.dart` shows ≥ 2 hits
    - `grep "_alertPolicy.clear" lib/features/monitoring/providers/audio_player_provider.dart` shows ≥ 2 hits
    - `grep "_alertPolicy.cancelAll" lib/features/monitoring/providers/audio_player_provider.dart` shows ≥ 2 hits (stopMonitoring + onDispose)
    - `grep "LocalNotificationsManager.fireAlert\\|LocalNotificationsManager.cancelAlert" lib/features/monitoring/providers/audio_player_provider.dart` exits 0
    - `grep "cause: 'wifi_reconnect'" lib/features/monitoring/providers/audio_player_provider.dart` exits 0
    - `grep "immediate: true" lib/features/monitoring/providers/audio_player_provider.dart` exits 0
    - `grep "HealthEventType.wifiDropped\\|HealthEventType.wifiReconnected\\|HealthEventType.alertFired" lib/features/monitoring/providers/audio_player_provider.dart` shows ≥ 3 lines
    - `grep "LocalNotificationsManager.init" lib/main.dart` exits 0
    - `grep "import 'core/services/local_notifications.dart'" lib/main.dart` exits 0
    - `flutter test test/features/monitoring/alerts/alert_timer_test.dart` reports 6 tests passed
    - `flutter test test/features/monitoring/reconnect/wifi_debounce_test.dart` reports 7 tests passed
    - `flutter analyze --no-preamble lib test` exits 0
    - `flutter test` full suite passes (no regressions)
  </acceptance_criteria>
  <done>
    RELY-01 fully covered. The three D-03 triggers (player events from 04-01, zombie from 04-02, WiFi-reconnect from this plan) all route through ReconnectSupervisor.requestReconnect. The D-04 5-minute one-shot alert fires via flutter_local_notifications on continuous non-playing, cancels on recovery, records alertFired events, and survives stopMonitoring teardown cleanly. main.dart initializes the notifications channel at startup alongside the foreground service.
  </done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| Android NotificationManager ↔ app | We pass camera name (from authoritative Protect API) as body interpolation; no user-typed strings. |
| connectivity_plus plugin ↔ Dart isolate | Stream may emit duplicate events (non-distinct per docs) — debounce is our responsibility. |
| Alert Timer ↔ Android Doze | Doze may defer Timer firing overnight — battery-opt exemption from Phase 3 is load-bearing. |

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-04-17 | Information Disclosure | Notification body visible on lock screen contains camera name (possible PII — "Nursery", child's room name) | mitigate | User-chosen camera names are already exposed via the FGS notification from Phase 3 (same visibility surface). Android lock-screen notification visibility is user-controlled via system settings (hide sensitive content). We do NOT include RTSP URLs, camera IPs, or auth tokens in notification content. Body copy is locked by UI-SPEC and contains no dynamic sensitive data beyond the camera name. |
| T-04-18 | Denial of Service | connectivity_plus rapid-flap spam triggers storm of immediate reconnects | mitigate | 1-second debounce in ConnectivityListener collapses rapid events. Supervisor dedupes via `inFlight` guard — simultaneous per-camera requests produce at most one open() call. Immediate-mode bypass only applies after a legitimate `none → wifi` transition (verified by tests). |
| T-04-19 | Spoofing | Malicious network event faking WiFi reconnect | accept | connectivity_plus uses Android's ConnectivityManager.NetworkCallback — requires system-level privilege to spoof. Not a realistic attack surface on a private baby-monitor device. |
| T-04-20 | Denial of Service | Alert timer fires during a brief <5min outage, waking parent needlessly | accept | 5-min threshold is the locked D-04 decision. User may dismiss without action; one-shot policy ensures no repeat nagging (D-04). |
| T-04-21 | Repudiation | Alert fired but user claims no notification received | mitigate | Every alert fire also records an `alertFired` HealthEvent with timestamp + cameraId. Visible in health summary screen (Plan 04-05). User can review post-hoc — distinguishes "app failed to fire" from "phone suppressed notification" (notification channel importance, Doze, OEM heads-up policy). |
| T-04-22 | Elevation of Privilege | Uncaught exception inside alert Timer callback or WiFi reconnect callback tears down AudioPlayerNotifier | mitigate | AlertPolicy.onFire wrapped in try/catch inside the timer body (see alert_policy.dart code). ConnectivityListener._scheduleDebounce body wrapped in try/catch. _onWifiReconnected iterates cameras under try/catch (inherited from supervisor.requestReconnect's own defensive patterns). |
| T-04-23 | Denial of Service | Android Doze defers Timer(5m) overnight, alert fires late | mitigate | RESEARCH §Pitfall 2: Phase 3 already requests battery-opt exemption; foreground service + exemption is documented as the mitigation. Fallback (RESEARCH §Pitfall 2 Fallback A): upgrade to `flutter_local_notifications.zonedSchedule` with `AndroidScheduleMode.exactAllowWhileIdle` if on-device overnight validation (VALIDATION.md Manual-Only Verifications #1, #4) proves unreliable. NOT adopted preemptively in this plan — keep implementation simple, validate on device. |
| T-04-24 | Information Disclosure | Notification permission denied (Android 13+) — user never sees alerts | mitigate | Permission is requested in MonitoringScreen.initState via `FlutterForegroundTask.checkNotificationPermission` + `requestNotificationPermission` (already covers both channels per RESEARCH §Section 4). RESEARCH §Pitfall 6 fallback: `alertFired` event is still recorded even when notification fails, so the health summary reflects intent. Future v2: show in-app banner when permission is denied. |
</threat_model>

<verification>
- `flutter pub get` resolves with connectivity_plus 7.x + flutter_local_notifications 19.x
- All 13+ unit tests across alert_timer_test.dart (6) and wifi_debounce_test.dart (7) pass deterministically via fake_async
- Grep confirms: AlertPolicy extraction, LocalNotificationsManager.init() called from main.dart, `cause: 'wifi_reconnect'` + `immediate: true` wire pattern at the connectivity handler, all three new HealthEventType variants (wifiDropped, wifiReconnected, alertFired) referenced in audio_player_provider.dart
- `flutter analyze --no-preamble lib test` stays clean
- Full `flutter test` suite remains green
</verification>

<success_criteria>
- RELY-01 complete: all three D-03 triggers (player events, zombie, WiFi reconnect) route through ReconnectSupervisor.
- D-04 implementation: 5-minute per-camera one-shot alert via flutter_local_notifications on Importance.max channel; cancels on recovery; records `alertFired` health event on every fire.
- No regressions to RELY-02 (UI from 04-03) or RELY-03 (zombie from 04-02).
- Manual-only verifications deferred to VALIDATION.md (on-device overnight run required before phase sign-off).
</success_criteria>

<output>
After completion, create `.planning/phases/04-reliability-overnight-monitoring/04-04-SUMMARY.md` capturing: AlertPolicy extraction rationale, the LocalNotificationsManager init ordering vs MediaKit.ensureInitialized + ForegroundServiceManager.init, WiFi-drop decision to NOT proactively reconnect (only record event), and any on-device behavioral findings (if available at summary-writing time).
</output>
