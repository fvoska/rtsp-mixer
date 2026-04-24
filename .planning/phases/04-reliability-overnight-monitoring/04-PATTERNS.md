# Phase 4: Reliability + Overnight Monitoring - Pattern Map

**Mapped:** 2026-04-24
**Files analyzed:** 12 (6 new, 6 modified)
**Analogs found:** 12 / 12

Every new/modified file has at least one strong in-repo analog. No file falls back to RESEARCH.md defaults. Excerpts below are load-bearing — executors copy these shapes into the new files.

---

## File Classification

| New/Modified File | Status | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|--------|------|-----------|----------------|---------------|
| `lib/features/monitoring/models/player_state.dart` | modified | model (enum extension) | value-object | (self — enum line 2) | exact |
| `lib/features/monitoring/models/health_event.dart` | NEW | model (immutable record + enum) | value-object | `lib/features/monitoring/models/player_state.dart` | role-match (model / copyWith) |
| `lib/features/monitoring/providers/health_events_provider.dart` | NEW | provider (Riverpod `Notifier`) | event-stream append + cap | `lib/core/providers/settings_provider.dart` (NotifierProvider) + `lib/core/logging/app_logger.dart` (ring buffer + cap) | exact (Notifier) + role-match (buffer) |
| `lib/features/monitoring/services/reconnect_supervisor.dart` | NEW | service (per-camera state machine, timers) | event-driven | `lib/features/monitoring/providers/audio_player_provider.dart` (timer + per-camera map pattern) | role-match (timer/map orchestration) |
| `lib/features/monitoring/services/zombie_watchdog.dart` | NEW | service (signal aggregator) | polling (piggybacks on `_levelPollTimer`) | `lib/features/monitoring/providers/audio_player_provider.dart` `_pollAudioLevels` (lines 319–432) | exact (polling + mpv-property read) |
| `lib/features/monitoring/services/connectivity_listener.dart` | NEW | service (stream subscription + debounce) | event-driven | `lib/features/monitoring/providers/audio_player_provider.dart` `_listenToPlayer` (lines 89–162) | role-match (Stream.listen → _subscriptions) |
| `lib/core/services/local_notifications.dart` | NEW | service (singleton init + fire/cancel) | request-response (OS boundary) | `lib/core/services/foreground_service.dart` (ForegroundServiceManager) | exact (same OS-plugin wrapper shape) |
| `lib/features/monitoring/providers/audio_player_provider.dart` | modified | provider (AsyncNotifier extension) | event-driven | (self) | exact |
| `lib/features/monitoring/widgets/camera_audio_card.dart` | modified | widget (render `reconnecting` state) | render | (self — lines 115–177 header Row, 180–187 level indicator, 321–325 LinearProgressIndicator) | exact |
| `lib/features/monitoring/screens/monitoring_screen.dart` | modified | screen (add AppBar IconButton) | navigation | (self — lines 152–163 AppBar actions) | exact |
| `lib/features/monitoring/screens/health_summary_screen.dart` | NEW | screen (scroll list + header cards) | read-only data display | `lib/features/monitoring/screens/log_screen.dart` | role-match (Scaffold + AppBar + scroll list + reactive) |
| `lib/core/services/foreground_service.dart` | modified | service (notification text builder) | request-response (OS boundary) | (self — `updateNotification` at lines 59–70) | exact |

---

## Pattern Assignments

### 1. `lib/features/monitoring/models/player_state.dart` (modified, model, value-object)

**Analog:** self — `CameraConnectionStatus` enum at line 2.

**Current enum** (line 2):
```dart
enum CameraConnectionStatus { idle, connecting, playing, error }
```

**Change:** Add `reconnecting` between `playing` and `error`:
```dart
enum CameraConnectionStatus { idle, connecting, playing, reconnecting, error }
```

**Derived getters to add** (mirror the existing `isLive` and `isError` at lines 141–142):
```dart
bool get isReconnecting => connectionStatus == CameraConnectionStatus.reconnecting;
```

**Rule:** `isLive` MUST remain `connectionStatus == CameraConnectionStatus.playing` only — do NOT change it to include `reconnecting`. Downstream widgets gate audio-level display / volume slider on `isLive`; reconnecting must disable those controls (see UI-SPEC interaction matrix).

---

### 2. `lib/features/monitoring/models/health_event.dart` (NEW, model, value-object)

**Analog:** `lib/features/monitoring/models/player_state.dart` — same "immutable record + enum in the same file" shape. `CameraAudioState` is `const`-constructible with required + optional fields; copy that.

**Imports pattern** (analog line 1 — pure Dart, no package imports for a pure data model):
```dart
// No imports needed — pure Dart.
```

**Enum pattern** (analog line 2):
```dart
enum HealthEventType {
  monitoringStarted,
  monitoringStopped,
  streamStarted,
  streamError,
  reconnectAttempt,
  reconnectSuccess,
  zombieDetected,
  wifiDropped,
  wifiReconnected,
  alertFired,
}
```

**Immutable record pattern** — mirror `CameraAudioState` constructor shape (analog lines 61–102):
```dart
class HealthEvent {
  final DateTime timestamp;
  final HealthEventType type;
  final String? cameraId;    // null for session-wide events
  final String? cameraName;  // cached for display (avoid lookup on render)
  final String? detail;      // free-text, e.g. error message or attempt number

  const HealthEvent({
    required this.timestamp,
    required this.type,
    this.cameraId,
    this.cameraName,
    this.detail,
  });
}
```

**Do NOT add `copyWith`** — HealthEvent is append-only; there is no mutation path. Omit to keep the class minimal (contrast with `CameraAudioState` which mutates via `copyWith` per Riverpod state updates).

---

### 3. `lib/features/monitoring/providers/health_events_provider.dart` (NEW, provider, event-stream append)

**Primary analog:** `lib/core/providers/settings_provider.dart` — `NotifierProvider` shape.
**Secondary analog:** `lib/core/logging/app_logger.dart` — ring-buffer cap logic (`_maxLines = 500` + `while (_buffer.length > _maxLines) { _buffer.removeFirst(); }` at lines 25–77).

**Imports pattern** (from settings_provider.dart lines 1–5):
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logging/app_logger.dart';
import '../models/health_event.dart';
```

**Notifier pattern** (from settings_provider.dart lines 59–67):
```dart
class HealthEventsNotifier extends Notifier<List<HealthEvent>> {
  static const _maxEvents = 1000; // D-17

  @override
  List<HealthEvent> build() => const [];

  // ... methods below
}
```

**Append-with-cap pattern** (adapt from app_logger.dart lines 74–77 — `addLast` + `while length > max removeFirst`):
```dart
void record(HealthEvent event) {
  final updated = [...state, event];
  if (updated.length > _maxEvents) {
    updated.removeRange(0, updated.length - _maxEvents);
  }
  state = updated;
  appLog('HEALTH', '${event.type.name} ${event.cameraName ?? 'session'} ${event.detail ?? ''}');
}

void clear() => state = const [];
```

**Provider registration pattern** (from settings_provider.dart lines 106–108):
```dart
final healthEventsProvider = NotifierProvider<HealthEventsNotifier, List<HealthEvent>>(
  HealthEventsNotifier.new,
);
```

**Rule:** Always log to `appLog('HEALTH', ...)` alongside the state update — the two consumers are independent (LogScreen + HealthSummaryScreen) and neither should miss events.

---

### 4. `lib/features/monitoring/services/reconnect_supervisor.dart` (NEW, service, event-driven)

**Analog:** `lib/features/monitoring/providers/audio_player_provider.dart` — per-camera `Map<String, X>` + `Timer` orchestration (lines 20–44).

**Per-camera map pattern** (analog lines 21–27):
```dart
// AudioPlayerNotifier pattern — maps keyed by cameraId, collected for disposal.
final Map<String, Player> _players = {};
final Map<String, VideoController> _videoControllers = {};
final List<StreamSubscription<dynamic>> _subscriptions = [];
Timer? _levelPollTimer;
final Map<String, double> _lastAudioPts = {};
```

**Apply the same shape to supervisor state:**
```dart
class _ReconnectState {
  int attempt = 0;
  Timer? retryTimer;
  Timer? alertTimer;
  bool alertFired = false;
  bool inFlight = false;
  DateTime? firstDropAt;
}

class ReconnectSupervisor {
  final Map<String, _ReconnectState> _perCamera = {};
  // …
}
```

**Teardown pattern** (copy from `onDispose` at analog lines 31–44, and `stopMonitoring` at 639–657):
```dart
void cancelAll() {
  for (final st in _perCamera.values) {
    st.retryTimer?.cancel();
    st.alertTimer?.cancel();
  }
  _perCamera.clear();
  appLog('RECONNECT', 'Supervisor cancelled all timers');
}
```

**Defensive recurring timer pattern** (mandatory per CLAUDE.md §Conventions — model it on analog lines 410–412 `catch (_) { /* Player may be disposed during poll. */ }` but extend to the three-layer depth required by the retry-forever rule D-02):
```dart
void _scheduleRetry(String cameraId, Duration delay) {
  final st = _perCamera.putIfAbsent(cameraId, () => _ReconnectState());
  st.retryTimer?.cancel();
  st.retryTimer = Timer(delay, () async {
    try {
      await _attemptReconnect(cameraId);
    } catch (e, stack) {
      appLog('RECONNECT', '$cameraId: retry crashed: $e\n$stack');
      // D-02: retry forever. Schedule the NEXT attempt even after a crash.
      try {
        st.attempt += 1;
        _scheduleRetry(cameraId, computeBackoff(st.attempt));
      } catch (_) {
        // Double-catch: if scheduling itself throws, the stream.error listener
        // will kick the supervisor again. Loop MUST NOT die here.
        appLog('RECONNECT', '$cameraId: scheduling itself failed — relying on stream.error fallback');
      }
    }
  });
}
```

**Dedup guard pattern** (RESEARCH Pattern 3 — Dart has no built-in; implement inline):
```dart
Future<void> requestReconnect(String cameraId, {required String cause, bool immediate = false}) async {
  final st = _perCamera.putIfAbsent(cameraId, () => _ReconnectState());
  if (st.inFlight) {
    appLog('RECONNECT', '$cameraId: suppressed duplicate ($cause)');
    return;
  }
  st.inFlight = true;
  try {
    // schedule or perform
  } finally {
    st.inFlight = false;
  }
}
```

**Rule:** Every `await` inside a timer callback MUST be inside a try/catch. Every `catch` MUST schedule the next attempt (retry forever, D-02). The supervisor may never exit its loop on its own.

**Health event emission:** Every state transition inside the supervisor emits via `ref.read(healthEventsProvider.notifier).record(...)`. Mirror the existing `appLog('AUDIO', ...)` pattern at analog line 184 — log AND record (two consumers).

---

### 5. `lib/features/monitoring/services/zombie_watchdog.dart` (NEW, service, polling)

**Analog:** `lib/features/monitoring/providers/audio_player_provider.dart` — `_pollAudioLevels` at lines 319–432.

**Polling structure pattern** (analog lines 319–413):
```dart
// Existing _pollAudioLevels shows the exact shape: iterate cameras, skip non-live,
// grab NativePlayer, read mpv properties with _tryGetProperty, accumulate deltas.
for (int i = 0; i < updated.cameras.length; i++) {
  final cam = updated.cameras[i];
  if (!cam.isLive) continue;
  final player = _players[cam.cameraId];
  if (player == null) continue;

  try {
    final np = player.platform as NativePlayer;
    final ptsStr = await np.getProperty('audio-pts');
    final pts = double.tryParse(ptsStr) ?? 0.0;
    final lastPts = _lastAudioPts[cam.cameraId] ?? 0.0;
    final ptsDelta = pts - lastPts;
    _lastAudioPts[cam.cameraId] = pts;
    // … existing logic
  } catch (_) {
    // Player may be disposed during poll.
  }
}
```

**`_tryGetProperty` helper** (analog lines 434–441 — copy verbatim; zombie watchdog needs the same try/catch + empty-string handling):
```dart
Future<String?> _tryGetProperty(NativePlayer np, String name) async {
  try {
    final v = await np.getProperty(name);
    return v.isEmpty ? null : v;
  } catch (_) {
    return null;
  }
}
```

**Signal-age counter pattern** — mirror `_lastAudioPts` map at analog line 25 + `_baselineLevel` at 26. Four parallel maps:
```dart
final Map<String, int> _ptsStallMs = {};           // ms since last PTS advance
final Map<String, int> _bufferingStuckMs = {};     // ms buffering=true sustained
final Map<String, int> _bitrateZeroMs = {};        // ms audio-bitrate = 0
final Map<String, int> _noAudioParamsMs = {};      // ms since last audioParams event
```

**Quorum / signal aggregation** (RESEARCH Section 2 — quorum ≥ 2; bitrate/audioParams alone are too noisy at stream start):
```dart
int _zombieScore(String cameraId) {
  int score = 0;
  if ((_ptsStallMs[cameraId] ?? 0) >= 60000) score += 2;   // weighted: PTS is most specific
  if ((_bufferingStuckMs[cameraId] ?? 0) >= 60000) score += 1;
  if ((_bitrateZeroMs[cameraId] ?? 0) >= 60000) score += 1;
  if ((_noAudioParamsMs[cameraId] ?? 0) >= 60000) score += 1;
  return score;
}

// Fire at score >= 2: PTS alone (weight 2) OR any two others.
```

**Rule:** Piggyback on existing `_levelPollTimer` at 500ms (analog line 316) rather than introducing a new timer. Increment age counters by `_pollInterval.inMilliseconds` (500) on each tick. Reset the counter to 0 on any positive signal (PTS advance, buffering=false, bitrate>0, audioParams event fires).

**Rule:** On zombie fire, call `ReconnectSupervisor.requestReconnect(cameraId, cause: 'zombie')` — do NOT tear down the player directly. The supervisor owns player lifecycle.

---

### 6. `lib/features/monitoring/services/connectivity_listener.dart` (NEW, service, event-driven)

**Analog:** `lib/features/monitoring/providers/audio_player_provider.dart` — `_listenToPlayer` lines 89–162 demonstrates the "subscribe to Stream, push onto `_subscriptions` list for unified cleanup" idiom.

**Subscription pattern** (analog line 90–94):
```dart
// Existing pattern — every subscription is added to _subscriptions for disposal.
_subscriptions.add(
  player.stream.playing.listen((playing) {
    appLog('STREAM', '$cameraName playing=$playing');
  }),
);
```

**Apply to connectivity:**
```dart
// Inside AudioPlayerNotifier.startMonitoring (or via the new listener class):
_subscriptions.add(
  Connectivity().onConnectivityChanged.listen((results) {
    try {
      final hasWifi = results.contains(ConnectivityResult.wifi);
      final hasEthernet = results.contains(ConnectivityResult.ethernet);
      _onConnectivityChange(hasWifi || hasEthernet);
    } catch (e) {
      appLog('CONN', 'Listener error: $e'); // never kill the subscription
    }
  }),
);
```

**Debounce pattern** — no in-repo analog; this is net-new. Follow RESEARCH Section 3 (Timer(1s) coalesce) and CLAUDE.md defensive-catch rule:
```dart
bool? _lastKnownHasLan;
Timer? _debounceTimer;

void _onConnectivityChange(bool hasLan) {
  _debounceTimer?.cancel();
  _debounceTimer = Timer(const Duration(seconds: 1), () {
    try {
      if (hasLan == _lastKnownHasLan) return;
      final wasOn = _lastKnownHasLan ?? true;
      _lastKnownHasLan = hasLan;
      if (!hasLan && wasOn) _onWifiDropped();
      else if (hasLan && !wasOn) _onWifiReconnected();
    } catch (e) {
      appLog('CONN', 'Debounce callback crashed: $e');
    }
  });
}
```

**Rule:** The `_debounceTimer` must be cancelled in `stopMonitoring` alongside supervisor timers (see Pattern 4 teardown pattern).

---

### 7. `lib/core/services/local_notifications.dart` (NEW, service, OS boundary)

**Analog:** `lib/core/services/foreground_service.dart` — `ForegroundServiceManager` is an exact shape-match: static class wrapping an OS-boundary plugin, idempotent `init()`, `start`/`updateNotification`/`stop` helpers, `appLog` on every entry point.

**Class shape** (copy from analog lines 13–81):
```dart
// Mirror ForegroundServiceManager: static-only class, singleton init, appLog everywhere.
class LocalNotificationsManager {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      const InitializationSettings(android: androidInit),
    );
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          'baby_monitor_alert',
          'Camera Offline Alerts',
          description: 'Fires when a camera has been offline for 5 minutes',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
        ));
    _initialized = true;
    appLog('NOTIF', 'Local notifications initialized');
  }
}
```

**Idempotency pattern** (analog lines 20–40 — `if (_initialized) return;` at top; log via `appLog` after init):
Exact copy.

**Fire-and-cancel helpers** (model on analog lines 43–76 — every public entry calls `appLog` first):
```dart
static Future<void> fireAlert({
  required String cameraId,
  required String cameraName,
}) async {
  await init(); // idempotent
  appLog('NOTIF', 'Fire alert for $cameraName');
  // … show call (see RESEARCH Section 4 for full AndroidNotificationDetails)
}

static Future<void> cancelAlert(String cameraId) async {
  appLog('NOTIF', 'Cancel alert for $cameraId');
  await _plugin.cancel(cameraId.hashCode);
}
```

**Rule:** Channel registration runs once at app init. Call `LocalNotificationsManager.init()` from the same place that calls `ForegroundServiceManager.init()` — look up the call site when planning (likely `main.dart` or auth bootstrap).

---

### 8. `lib/features/monitoring/providers/audio_player_provider.dart` (modified, provider)

**Analog:** self — extending existing patterns, NOT introducing a new paradigm.

**Existing onDispose pattern to extend** (lines 31–44):
```dart
ref.onDispose(() {
  _levelPollTimer?.cancel();
  for (final sub in _subscriptions) {
    sub.cancel();
  }
  _subscriptions.clear();
  _videoControllers.clear();
  for (final p in _players.values) {
    p.dispose();
  }
  _players.clear();
  _lastAudioPts.clear();
  _baselineLevel.clear();
});
```

**Add to onDispose and to stopMonitoring (lines 639–657):**
```dart
_reconnectSupervisor.cancelAll();   // NEW
_zombieWatchdog.reset();            // NEW
_connectivityListener.cancel();     // NEW (or rely on _subscriptions)
ref.read(healthEventsProvider.notifier).record(HealthEvent(
  timestamp: DateTime.now(),
  type: HealthEventType.monitoringStopped,
));
```

**Existing player listener pattern to extend** (lines 100–104):
```dart
_subscriptions.add(
  player.stream.error.listen((error) {
    appLog('STREAM', '$cameraName error=$error');
  }),
);
```

**Extended version** — add supervisor request and health event, preserve the existing log line:
```dart
_subscriptions.add(
  player.stream.error.listen((error) {
    appLog('STREAM', '$cameraName error=$error');
    ref.read(healthEventsProvider.notifier).record(HealthEvent(
      timestamp: DateTime.now(),
      type: HealthEventType.streamError,
      cameraId: cameraId,
      cameraName: cameraName,
      detail: error.toString(),
    ));
    _reconnectSupervisor.requestReconnect(cameraId, cause: 'player_error');
  }),
);
```

Same extension applies to `player.stream.completed` (analog lines 96–99) and `player.stream.buffering` (lines 105–122).

**Existing status transition pattern** (analog lines 114–120) — use this exact `copyWithCamera + copyWith(connectionStatus: ...)` shape when the supervisor flips to `reconnecting`:
```dart
state = AsyncData(current.copyWithCamera(idx,
  cam.copyWith(connectionStatus: CameraConnectionStatus.reconnecting)));
```

**Existing notification update text-builder pattern** (analog lines 294–306, repeated 419–430) — extend to include `reconnecting` in the status string. The current code already falls through to `' (${c.connectionStatus.name})'` so NO change is strictly required, but verify copy reads well: `"Monitoring: Nursery (reconnecting), Bedroom"`.

**Rule:** Do NOT change the `_pollInterval = 500ms` (line 312). Zombie watchdog piggybacks on this exact timer — changing it ripples into false-positive thresholds.

---

### 9. `lib/features/monitoring/widgets/camera_audio_card.dart` (modified, widget)

**Analog:** self — adding a fourth branch to existing status-aware rendering at lines 115–177.

**Status dot pattern** (existing, lines 117–129) — add a fourth color branch:
```dart
Container(
  width: 8,
  height: 8,
  decoration: BoxDecoration(
    shape: BoxShape.circle,
    color: cs.isLive
        ? AppTheme.statusOnline
        : cs.isError
            ? AppTheme.statusOffline
            : cs.connectionStatus == CameraConnectionStatus.reconnecting  // NEW
                ? theme.colorScheme.tertiary                               // NEW
                : theme.colorScheme.onSurface.withValues(alpha: 0.5),
  ),
),
```

**Status-text pattern** (existing, lines 137–153) — add a `reconnecting` branch mirroring the `Connecting...` / `Live` / error branches. Per UI-SPEC, inline spinner + text in a Row:
```dart
if (cs.connectionStatus == CameraConnectionStatus.reconnecting)
  Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(
          strokeWidth: 2.0,
          valueColor: AlwaysStoppedAnimation(theme.colorScheme.tertiary),
        ),
      ),
      const SizedBox(width: Spacing.xs),
      Text(
        'Reconnecting…',
        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.tertiary),
      ),
    ],
  ),
```

**Header-tint wrapping pattern** — per UI-SPEC §Component Inventory #1: wrap the header `Row` (lines 115–177) in a `Container` with `tertiaryContainer @ alpha 0.3` when `reconnecting`. Do NOT tint the outer `AnimatedContainer` (which hosts the activity border — preserve that behavior).

**LinearProgressIndicator gating pattern** (existing, lines 321–325):
```dart
if (isConnecting)
  const Padding(
    padding: EdgeInsets.symmetric(vertical: Spacing.sm),
    child: LinearProgressIndicator(),
  ),
```
**Do NOT add a `reconnecting` branch here.** Per UI-SPEC interaction matrix: `connecting` gets the linear bar, `reconnecting` gets the inline spinner — never both.

**Volume slider gating pattern** (existing, line 339) — already gates on `cs.isLive`. Since `isLive` stays false for `reconnecting`, the slider is automatically disabled. No change needed.

**Audio level indicator gating pattern** (existing, lines 180–187) — already gates on `cs.isLive`. No change needed.

**Rule:** Every color must resolve through `theme.colorScheme` or `AppTheme.statusOnline/statusOffline` — do NOT introduce `Colors.amber` or new `Color(0x...)` constants. `colorScheme.tertiary` IS the amber from the seed `#5C6BC0`.

---

### 10. `lib/features/monitoring/screens/monitoring_screen.dart` (modified, screen)

**Analog:** self — existing `AppBar.actions` at lines 152–163.

**Existing AppBar actions pattern**:
```dart
appBar: AppBar(
  title: const Text('Monitoring'),
  actions: [
    IconButton(
      icon: Icon(_globalVideo ? Icons.videocam : Icons.videocam_off),
      tooltip: _globalVideo ? 'Hide all video previews' : 'Show all video previews',
      onPressed: _toggleGlobalVideo,
    ),
  ],
),
```

**Change:** Add a new `IconButton` **before** the existing video-toggle (UI-SPEC Component #2). Use `Navigator.push` (not GoRouter) — same pattern used elsewhere for modal-style screens:
```dart
actions: [
  IconButton(
    icon: const Icon(Icons.monitor_heart_outlined),
    tooltip: 'Open health summary',
    onPressed: () => Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const HealthSummaryScreen()),
    ),
  ),
  IconButton(  // existing, unchanged
    icon: Icon(_globalVideo ? Icons.videocam : Icons.videocam_off),
    tooltip: _globalVideo ? 'Hide all video previews' : 'Show all video previews',
    onPressed: _toggleGlobalVideo,
  ),
],
```

**Rule:** No `ref.watch` on the new IconButton (UI-SPEC §Registry Safety — no badge/dot on the icon in v1).

---

### 11. `lib/features/monitoring/screens/health_summary_screen.dart` (NEW, screen)

**Analog:** `lib/features/monitoring/screens/log_screen.dart` — closest shape: Scaffold + AppBar + scrollable body + reactive listener pattern.

**Imports pattern** (from log_screen.dart lines 1–4 + Riverpod addition since we use `ref.watch`):
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/spacing.dart';
import '../models/health_event.dart';
import '../models/player_state.dart';
import '../providers/audio_player_provider.dart';
import '../providers/health_events_provider.dart';
```

**Scaffold shell pattern** (analog lines 55–93):
```dart
return Scaffold(
  appBar: AppBar(
    title: const Text('Health summary'),
  ),
  body: /* … */,
);
```

**Reactivity pattern** — analog uses `AppLogger.instance.addListener` (imperative); the new screen uses Riverpod (declarative). Use `ConsumerWidget` (not `ConsumerStatefulWidget`) since there's no local UI state in v1 per UI-SPEC. `ref.watch` replaces the `setState` callback pattern at analog lines 31–41:
```dart
class HealthSummaryScreen extends ConsumerWidget {
  const HealthSummaryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(healthEventsProvider);
    final monState = ref.watch(audioPlayerProvider).value;
    // …
  }
}
```

**Scrollable list pattern** (analog lines 94–111 — `ListView.builder(controller, itemCount, itemBuilder)`). Apply the "reverse the data, not the list" rule from UI-SPEC:
```dart
Expanded(
  child: ListView.builder(
    itemCount: events.length,
    itemBuilder: (_, i) {
      final reversed = events.reversed.toList();
      return _EventRow(event: reversed[i]);
    },
  ),
),
```
(Prefer computing `reversed` once outside itemBuilder — the above is schematic. Planner/executor decides placement.)

**Private row widget pattern** (analog `_AudioLevelIndicator` lines 368–422, `_StreamInfoPanel` lines 424–530, `_OverlayButton` lines 532–561) — use a file-private `_EventRow extends StatelessWidget` with named required fields. This is the established convention for leaf row widgets.

**Typography pattern** — all text MUST resolve through `theme.textTheme` (analog line 134 `theme.textTheme.titleMedium`, line 138 `theme.textTheme.bodyMedium`). UI-SPEC Copywriting Contract locks exact styles per element.

**Severity → color mapping** — use theme roles, not hardcoded `Colors.*`. Follow analog line 121–123:
```dart
// In analog:
if (line.contains('[FGS]')) return Colors.tealAccent;
```
**Anti-pattern for this new screen.** Use `AppTheme.statusOnline`, `AppTheme.statusOffline`, `theme.colorScheme.tertiary`, `theme.colorScheme.primary`, `theme.colorScheme.onSurfaceVariant` per UI-SPEC's severity table. **Do not repeat the log_screen.dart `Colors.tealAccent` pattern** — that's a Phase-1 concession, not the target.

**Rule:** No filter/search input on this screen (UI-SPEC §Out of Scope). The analog's `TextField` at lines 79–91 is explicitly excluded here.
**Rule:** No `Clipboard` / copy button (UI-SPEC §Out of Scope). The analog's `IconButton(icon: Icons.copy, ...)` at lines 64–73 is excluded.

---

### 12. `lib/core/services/foreground_service.dart` (modified, service)

**Analog:** self — existing `updateNotification` at lines 59–70.

**Existing pattern:**
```dart
static Future<void> updateNotification({
  required String text,
  String title = 'Baby Monitor Active',
  List<NotificationButton>? notificationButtons,
}) async {
  appLog('FGS', 'Notification update: $text');
  await FlutterForegroundTask.updateService(
    notificationTitle: title,
    notificationText: text,
    notificationButtons: notificationButtons,
  );
}
```

**Change:** No signature change required. Callers (e.g., `audio_player_provider.dart:294–306, 419–430`) already build status-aware text via `c.connectionStatus.name` interpolation — the new `reconnecting` enum value flows through automatically. Verify that the resulting string reads well and is ≤ ~120 chars (Android truncates long notification text).

**Optional helper** — if the planner wants a centralized text-builder (currently duplicated at analog 294–306 and 419–430), extract to:
```dart
static String buildStatusText(List<CameraAudioState> cameras) {
  final parts = cameras.map((c) {
    if (c.connectionStatus == CameraConnectionStatus.playing) return c.cameraName;
    return '${c.cameraName} (${c.connectionStatus.name})';
  });
  return 'Monitoring: ${parts.join(", ")}';
}
```
This is a DRY win from Phase 2 technical debt; not strictly required for Phase 4 but encouraged.

---

## Shared Patterns

### Defensive Error Handling (CLAUDE.md §Conventions — non-negotiable)

**Source:** `lib/features/monitoring/providers/audio_player_provider.dart` — pervasive.

**Apply to:** every new file.

**Pattern A — silent degrade on property read** (analog lines 434–441):
```dart
Future<String?> _tryGetProperty(NativePlayer np, String name) async {
  try {
    final v = await np.getProperty(name);
    return v.isEmpty ? null : v;
  } catch (_) {
    return null;
  }
}
```

**Pattern B — swallow with narrow scope during iteration** (analog lines 333–412):
```dart
for (...) {
  try {
    // do the thing
  } catch (_) {
    // Player may be disposed during poll.
  }
}
```

**Pattern C — catch + log on OS boundary** (analog lines 295–306):
```dart
try {
  final text = _buildNotificationText(...);
  await ForegroundServiceManager.updateNotification(text: text);
} catch (e) {
  appLog('FGS', 'Failed to update notification: $e');
}
```

**Pattern D — triple-layer for retry-forever loops** (see Pattern 4 in file #4 above).

**Non-negotiable rule:** Every new `try/catch` MUST either (a) recover with a sensible default, (b) log via `appLog` AND continue, or (c) re-raise only when the calling stream is already dead. No `catch (e) { print(e); }` without recovery — parents fall asleep trusting this.

### Structured Logging (CLAUDE.md §Conventions)

**Source:** `lib/core/logging/app_logger.dart` — `appLog(tag, message)` at line 83.

**Apply to:** every service, every state transition, every OS-boundary call.

**Tag conventions in use** (grep existing usage):
- `AUDIO` — AudioPlayerNotifier lifecycle and volume operations
- `STREAM` — per-player stream events
- `MPV` — raw mpv log passthrough
- `FGS` — foreground service
- `UI` — user interactions
- `LIFECYCLE` — app foreground/background transitions
- `SETTINGS` — settings_provider
- `AUDIO_SERVICE` — audio_handler (MediaSession)

**New tags for Phase 4** (recommended):
- `RECONNECT` — ReconnectSupervisor
- `ZOMBIE` — ZombieWatchdog
- `CONN` — connectivity_listener
- `NOTIF` — LocalNotificationsManager
- `HEALTH` — HealthEventsNotifier

**Pattern** — short uppercase tag + descriptive message. The AppLogger auto-prefixes with timestamp (analog line 62) so logs interleave cleanly in LogScreen and `/tmp/rtsp_mixer.log`.

### Riverpod NotifierProvider registration

**Source:** `lib/core/providers/settings_provider.dart` lines 59–108.

**Apply to:** `health_events_provider.dart`.

```dart
class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() { /* initial state */ return const AppSettings(); }
  // methods mutate via `state = state.copyWith(...)`
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);
```

### Per-camera Map orchestration

**Source:** `lib/features/monitoring/providers/audio_player_provider.dart` lines 21–27, 41–43.

**Apply to:** `reconnect_supervisor.dart`, `zombie_watchdog.dart`.

Every per-camera mutable structure lives in a `Map<String, T>` keyed by `cameraId`, and every such map is explicitly cleared in `onDispose`/`stopMonitoring`. No exceptions — leaked state across `start/stop` cycles is what kills overnight reliability.

### Widget test pattern (for Wave 0 stubs)

**Source:** `test/features/monitoring/player_state_test.dart` (exists, simple).

**Apply to:** `player_state_test.dart` (extend with `reconnecting` case), new backoff / supervisor / watchdog / health tests.

**Test structure** (analog lines 4–73):
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:rtsp_mixer/features/monitoring/models/player_state.dart';

void main() {
  group('CameraAudioState', () {
    test('default values are volume=100, pan=0, isMuted=false, idle', () {
      const state = CameraAudioState(cameraId: 'cam1', cameraName: 'Nursery');
      expect(state.connectionStatus, CameraConnectionStatus.idle);
    });
    // …
  });
}
```

**Extension for Phase 4:**
```dart
test('reconnecting is a distinct status and is not live', () {
  const state = CameraAudioState(
    cameraId: 'cam1',
    cameraName: 'Nursery',
    connectionStatus: CameraConnectionStatus.reconnecting,
  );
  expect(state.connectionStatus, CameraConnectionStatus.reconnecting);
  expect(state.isLive, false);
  expect(state.isError, false);
});
```

**fake_async pattern** (NEW dep per VALIDATION.md Wave 0) — no in-repo analog; follow the `fake_async ^1.3.0` package README. Needed for backoff / alert-timer / debounce tests. Planner should reference the package docs when writing these tests.

**Widget test pattern** (for `camera_audio_card_test.dart`, `health_summary_screen_test.dart`) — no existing widget test in repo. Planner must create the pattern from scratch; recommend using `ProviderScope(overrides: [...])` + `MaterialApp(home: ...)` scaffolding. This is the one gap where RESEARCH.md Section 7 defaults apply rather than an in-repo analog.

---

## No Analog Found

None. Every file has at least one strong in-repo analog as mapped above. The only area with no full in-repo analog is the **widget test scaffolding** — no existing `testWidgets(...)` case in `/test`. Planner writing the first widget test for Phase 4 must reference the `flutter_test` + `flutter_riverpod` package docs for `ProviderScope(overrides: [...])` usage.

---

## Metadata

**Analog search scope:**
- `lib/features/monitoring/` (providers, models, services, screens, widgets, helpers)
- `lib/core/` (services, logging, providers, theme, models)
- `test/features/monitoring/`

**Files scanned:** 16 source files + 4 test files + 1 pubspec + theme/spacing tokens.

**Pattern extraction date:** 2026-04-24.

**Convention enforcement summary:**
- All color refs go through `Theme.of(context).colorScheme` or `AppTheme.status*`.
- All spacing goes through `Spacing.*` tokens.
- All logging goes through `appLog(tag, message)`.
- All per-camera state lives in `Map<String, T>` keyed by `cameraId`.
- All timers / subscriptions are cancelled in `stopMonitoring` AND `onDispose`.
- Every `await` in a timer callback is inside try/catch that schedules the next attempt (D-02 retry-forever).
- No new `TextStyle` / `Color` / `Spacing.*` constants introduced.
