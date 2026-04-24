---
phase: 04-reliability-overnight-monitoring
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - pubspec.yaml
  - lib/features/monitoring/models/player_state.dart
  - lib/features/monitoring/models/health_event.dart
  - lib/features/monitoring/providers/health_events_provider.dart
  - lib/features/monitoring/services/reconnect_supervisor.dart
  - lib/features/monitoring/providers/audio_player_provider.dart
  - test/features/monitoring/models/player_state_test.dart
  - test/features/monitoring/health/event_stream_cap_test.dart
  - test/features/monitoring/reconnect/backoff_test.dart
  - test/features/monitoring/reconnect/trigger_dedupe_test.dart
  - test/features/monitoring/reconnect/state_machine_test.dart
  - test/features/monitoring/reconnect/defensive_recovery_test.dart
autonomous: true
requirements: [RELY-01, RELY-02]
tags: [reconnect, backoff, baby-monitor, rtsp, media_kit, flutter, riverpod]

must_haves:
  truths:
    - "CameraConnectionStatus enum includes `reconnecting` between `playing` and `error`"
    - "App auto-reconnects dropped RTSP streams using exponential backoff (1/2/4/8/16/30/30...s) with ±20% jitter"
    - "Reconnect loop retries forever — never gives up while monitoring is active"
    - "Reconnect triggered by Player.stream.error and Player.stream.completed events (triggers a, partial D-03)"
    - "Multiple simultaneous reconnect triggers within the same event tick result in at most one in-flight reconnect"
    - "HealthEventsNotifier records events in a capped (1000) in-memory list"
    - "Session boundary: startMonitoring clears health events then records monitoringStarted; stopMonitoring records monitoringStopped and cancels all supervisor timers"
    - "Reconnect loop survives exceptions thrown inside the retry timer callback"
  artifacts:
    - path: "pubspec.yaml"
      provides: "connectivity_plus + flutter_local_notifications runtime deps, fake_async dev dep"
      contains: "connectivity_plus: ^7.1.1"
    - path: "lib/features/monitoring/models/player_state.dart"
      provides: "CameraConnectionStatus with reconnecting variant + isReconnecting getter"
      contains: "reconnecting"
    - path: "lib/features/monitoring/models/health_event.dart"
      provides: "HealthEventType enum + HealthEvent immutable record"
      contains: "enum HealthEventType"
    - path: "lib/features/monitoring/providers/health_events_provider.dart"
      provides: "HealthEventsNotifier with record/clear + 1000-event cap"
      contains: "class HealthEventsNotifier"
    - path: "lib/features/monitoring/services/reconnect_supervisor.dart"
      provides: "ReconnectSupervisor: per-camera backoff state, dedup, retry-forever timer"
      contains: "class ReconnectSupervisor"
    - path: "lib/features/monitoring/providers/audio_player_provider.dart"
      provides: "Wires supervisor into AudioPlayerNotifier; emits health events on stream events; cancels supervisor on stopMonitoring"
      contains: "ReconnectSupervisor"
    - path: "test/features/monitoring/reconnect/backoff_test.dart"
      provides: "Unit tests for computeBackoff math + jitter bounds"
    - path: "test/features/monitoring/reconnect/trigger_dedupe_test.dart"
      provides: "Dedup guard test"
    - path: "test/features/monitoring/reconnect/defensive_recovery_test.dart"
      provides: "Timer-exception recovery test (loop survives)"
  key_links:
    - from: "lib/features/monitoring/providers/audio_player_provider.dart"
      to: "lib/features/monitoring/services/reconnect_supervisor.dart"
      via: "AudioPlayerNotifier holds ReconnectSupervisor field, calls requestReconnect on stream.error/completed"
      pattern: "_reconnectSupervisor\\.requestReconnect"
    - from: "lib/features/monitoring/providers/audio_player_provider.dart"
      to: "lib/features/monitoring/providers/health_events_provider.dart"
      via: "ref.read(healthEventsProvider.notifier).record(...) on lifecycle + stream events"
      pattern: "healthEventsProvider\\.notifier"
    - from: "lib/features/monitoring/services/reconnect_supervisor.dart"
      to: "media_kit Player.open()"
      via: "Supervisor calls player.stop() + _applyPlaybackTuning() + player.open(Media(url)) on the same Player instance"
      pattern: "player\\.open\\(Media"
---

<objective>
Establish the reconnect foundation for Phase 4: add the two new pub.dev dependencies + fake_async, expand CameraConnectionStatus with `reconnecting`, create HealthEvent model + HealthEventsNotifier, create ReconnectSupervisor with exponential-backoff + dedup + retry-forever timer, and wire the supervisor into AudioPlayerNotifier so that Player.stream.error and Player.stream.completed both enqueue a supervisor reconnect. Also write Wave 0 test scaffolding for every test file that downstream plans will need.

Purpose: RELY-01 (core reconnect) + RELY-02 (enum + status plumbing). This plan is load-bearing for baby-monitor overnight trust — every other Phase 4 plan depends on the supervisor existing and the enum having `reconnecting`.
Output: Working backoff + dedup + retry-forever loop driven by player events (triggers a from D-03). WiFi + zombie triggers come from later plans.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@CLAUDE.md
@.planning/PROJECT.md
@.planning/ROADMAP.md
@.planning/STATE.md
@.planning/REQUIREMENTS.md
@.planning/phases/04-reliability-overnight-monitoring/04-CONTEXT.md
@.planning/phases/04-reliability-overnight-monitoring/04-RESEARCH.md
@.planning/phases/04-reliability-overnight-monitoring/04-PATTERNS.md
@.planning/phases/04-reliability-overnight-monitoring/04-VALIDATION.md

<interfaces>
<!-- Key types and patterns executors need. Extracted from existing code. -->
<!-- Executors MUST follow these verbatim — no alternative shapes allowed. -->

From lib/features/monitoring/models/player_state.dart (current, BEFORE this plan):
```dart
enum CameraConnectionStatus { idle, connecting, playing, error }

class CameraAudioState {
  final String cameraId;
  final String cameraName;
  // ...
  final CameraConnectionStatus connectionStatus;
  final String? errorMessage;
  // copyWith present
  bool get isLive => connectionStatus == CameraConnectionStatus.playing;
  bool get isError => connectionStatus == CameraConnectionStatus.error;
  bool get isSuspiciouslySilent => isLive && silenceDuration > 10.0;
}
```

Target AFTER this plan: enum = `idle, connecting, playing, reconnecting, error`; new getter `isReconnecting` added after existing `isError`. `isLive` MUST remain `== playing` only (per PATTERNS.md Rule #1).

From lib/features/monitoring/providers/audio_player_provider.dart (pattern excerpts):
```dart
// Line 21-26: per-camera state is always a Map<String, T> keyed by cameraId
final Map<String, Player> _players = {};
final List<StreamSubscription<dynamic>> _subscriptions = [];
Timer? _levelPollTimer;
final Map<String, double> _lastAudioPts = {};

// Line 100-104: existing stream.error listener (to be extended)
_subscriptions.add(
  player.stream.error.listen((error) {
    appLog('STREAM', '$cameraName error=$error');
  }),
);

// Line 434-441: _tryGetProperty helper (copy for zombie later; referenced here)
Future<String?> _tryGetProperty(NativePlayer np, String name) async {
  try {
    final v = await np.getProperty(name);
    return v.isEmpty ? null : v;
  } catch (_) {
    return null;
  }
}

// Line 639-657: stopMonitoring (extended below)
Future<void> stopMonitoring() async {
  _levelPollTimer?.cancel();
  _lastAudioPts.clear();
  for (final sub in _subscriptions) { sub.cancel(); }
  _subscriptions.clear();
  for (final player in _players.values) {
    await player.stop();
    await player.dispose();
  }
  _players.clear();
  state = const AsyncData(MonitoringState());
}
```

From lib/core/providers/settings_provider.dart (NotifierProvider analog for health_events_provider):
```dart
class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() => const AppSettings();
  // state = state.copyWith(...)
}
final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);
```

From lib/core/logging/app_logger.dart (ring-buffer cap analog):
```dart
// addLast + while buffer.length > _maxLines -> removeFirst()
// _maxLines = 500 in app_logger; HealthEvents uses _maxEvents = 1000
```

appLog tag conventions (CLAUDE.md): `AUDIO`, `STREAM`, `FGS`. NEW for Phase 4: `RECONNECT`, `HEALTH`.
</interfaces>
</context>

<tasks>

<task type="auto" tdd="true">
  <name>Task 1: Wave 0 — dependencies, enum extension, models, health events provider, test stubs</name>
  <files>
    pubspec.yaml,
    lib/features/monitoring/models/player_state.dart,
    lib/features/monitoring/models/health_event.dart,
    lib/features/monitoring/providers/health_events_provider.dart,
    test/features/monitoring/models/player_state_test.dart,
    test/features/monitoring/health/event_stream_cap_test.dart,
    test/features/monitoring/reconnect/backoff_test.dart,
    test/features/monitoring/reconnect/trigger_dedupe_test.dart,
    test/features/monitoring/reconnect/state_machine_test.dart,
    test/features/monitoring/reconnect/defensive_recovery_test.dart
  </files>
  <read_first>
    - .planning/phases/04-reliability-overnight-monitoring/04-PATTERNS.md §1 (enum extension), §2 (HealthEvent shape), §3 (HealthEventsNotifier), §Shared Patterns > Widget test pattern
    - .planning/phases/04-reliability-overnight-monitoring/04-VALIDATION.md §Wave 0 Requirements
    - .planning/phases/04-reliability-overnight-monitoring/04-RESEARCH.md §Standard Stack (version pins), §Section 6 (HealthEventsNotifier), §Section 7 (test infrastructure)
    - .planning/phases/04-reliability-overnight-monitoring/04-CONTEXT.md §decisions D-09, D-13, D-14, D-15, D-17
    - CLAUDE.md §Conventions > Defensive error handling, §media_kit FFmpeg build limitations
    - lib/features/monitoring/models/player_state.dart (entire file — see current enum on line 2 and getters on lines 141–143)
    - lib/core/providers/settings_provider.dart (NotifierProvider shape for health_events_provider)
    - lib/core/logging/app_logger.dart (appLog signature + buffer-cap analog)
    - test/features/monitoring/player_state_test.dart (existing — MUST be extended in place)
    - pubspec.yaml (current — confirm no existing connectivity_plus / flutter_local_notifications / fake_async)
  </read_first>
  <behavior>
    - Test 1 (player_state_test.dart): `CameraConnectionStatus.values` contains `reconnecting`; the order is `[idle, connecting, playing, reconnecting, error]`
    - Test 2 (player_state_test.dart): `CameraAudioState(connectionStatus: CameraConnectionStatus.reconnecting).isReconnecting == true`; `.isLive == false`; `.isError == false`
    - Test 3 (event_stream_cap_test.dart): appending 1,001 HealthEvents via HealthEventsNotifier.record leaves 1,000 in state; the oldest is dropped; events preserve chronological order (oldest first)
    - Test 4 (event_stream_cap_test.dart): HealthEventsNotifier.clear() empties state to const []
    - Test 5 (event_stream_cap_test.dart): appending the first event yields `state.length == 1` and `state.first.type == appended.type`
    - Other test stub files (backoff_test, trigger_dedupe_test, state_machine_test, defensive_recovery_test) contain a single no-op `test('scaffold', () {});` inside the relevant `group(...)` — real assertions land in Task 2. Wave 0 is about making the files exist and importable.
  </behavior>
  <action>
    Step A — pubspec.yaml: add three dependency entries (per RESEARCH.md §Standard Stack + §9):
      Under `dependencies:` (alphabetical between existing entries), add:
        connectivity_plus: ^7.1.1
        flutter_local_notifications: ^19.0.0
      Under `dev_dependencies:` (after `mockito: ^5.5.0`), add:
        fake_async: ^1.3.0
      Pin `flutter_local_notifications: ^19.0.0` explicitly (not ^21.x — project is on Dart `^3.9.2`, and 20.x+ requires Dart 3.10 per RESEARCH.md §Standard Stack Dart SDK note).
      Run `flutter pub get` after editing. Resolve any version conflicts per RESEARCH.md §Standard Stack before continuing.

    Step B — lib/features/monitoring/models/player_state.dart (per D-09):
      1. Replace line 2 with:
         `enum CameraConnectionStatus { idle, connecting, playing, reconnecting, error }`
      2. Add a new getter immediately after `bool get isError => ...;` (current line 142):
         `bool get isReconnecting => connectionStatus == CameraConnectionStatus.reconnecting;`
      3. DO NOT modify `isLive` — it MUST remain `connectionStatus == CameraConnectionStatus.playing` only (PATTERNS.md §1 Rule). The volume slider + audio level indicator gate on isLive; they must stay disabled during reconnecting.
      4. DO NOT modify `copyWith` — existing signature already passes connectionStatus through.

    Step C — lib/features/monitoring/models/health_event.dart (NEW, per D-15 + PATTERNS.md §2):
      Create the file with exactly this content (pure Dart, no imports):
      ```dart
      /// Event types captured in the overnight health summary (D-15).
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

      /// Single append-only health event. No copyWith — events are immutable records.
      class HealthEvent {
        final DateTime timestamp;
        final HealthEventType type;
        final String? cameraId;   // null for session-wide events
        final String? cameraName; // cached for display (avoid lookup on render)
        final String? detail;     // free-text (error message, attempt number, signal summary)

        const HealthEvent({
          required this.timestamp,
          required this.type,
          this.cameraId,
          this.cameraName,
          this.detail,
        });
      }
      ```

    Step D — lib/features/monitoring/providers/health_events_provider.dart (NEW, per D-14 + D-17 + PATTERNS.md §3):
      ```dart
      import 'package:flutter_riverpod/flutter_riverpod.dart';

      import '../../../core/logging/app_logger.dart';
      import '../models/health_event.dart';

      /// In-memory session-scoped health event recorder (D-13, D-14).
      /// Capped at 1000 events (D-17) — drops oldest when full.
      class HealthEventsNotifier extends Notifier<List<HealthEvent>> {
        static const _maxEvents = 1000; // D-17

        @override
        List<HealthEvent> build() => const [];

        /// Append an event. Drops the oldest when the cap is exceeded.
        /// Also logs via appLog('HEALTH', ...) so LogScreen sees it (two consumers).
        void record(HealthEvent event) {
          final updated = [...state, event];
          if (updated.length > _maxEvents) {
            updated.removeRange(0, updated.length - _maxEvents);
          }
          state = updated;
          appLog('HEALTH', '${event.type.name} ${event.cameraName ?? 'session'} ${event.detail ?? ''}');
        }

        /// Reset the list (called on startMonitoring per D-13).
        void clear() => state = const [];
      }

      final healthEventsProvider =
          NotifierProvider<HealthEventsNotifier, List<HealthEvent>>(
        HealthEventsNotifier.new,
      );
      ```

    Step E — test/features/monitoring/models/player_state_test.dart (EXTEND existing, at end of main()):
      Append INSIDE the existing `group('CameraAudioState', () { ... });` block, before the closing `});`:
      ```dart
      test('reconnecting status exists and is distinct from playing/error', () {
        const state = CameraAudioState(
          cameraId: 'cam1',
          cameraName: 'Nursery',
          connectionStatus: CameraConnectionStatus.reconnecting,
        );
        expect(state.connectionStatus, CameraConnectionStatus.reconnecting);
        expect(state.isLive, false);
        expect(state.isError, false);
        expect(state.isReconnecting, true);
      });

      test('enum order is [idle, connecting, playing, reconnecting, error]', () {
        expect(CameraConnectionStatus.values, [
          CameraConnectionStatus.idle,
          CameraConnectionStatus.connecting,
          CameraConnectionStatus.playing,
          CameraConnectionStatus.reconnecting,
          CameraConnectionStatus.error,
        ]);
      });
      ```

    Step F — test/features/monitoring/health/event_stream_cap_test.dart (NEW):
      ```dart
      import 'package:flutter_riverpod/flutter_riverpod.dart';
      import 'package:flutter_test/flutter_test.dart';
      import 'package:rtsp_mixer/features/monitoring/models/health_event.dart';
      import 'package:rtsp_mixer/features/monitoring/providers/health_events_provider.dart';

      void main() {
        group('HealthEventsNotifier', () {
          late ProviderContainer container;

          setUp(() {
            container = ProviderContainer();
          });

          tearDown(() {
            container.dispose();
          });

          HealthEvent _evt(int i) => HealthEvent(
                timestamp: DateTime.fromMillisecondsSinceEpoch(i),
                type: HealthEventType.reconnectAttempt,
                detail: 'attempt $i',
              );

          test('record appends a single event', () {
            container.read(healthEventsProvider.notifier).record(_evt(1));
            expect(container.read(healthEventsProvider).length, 1);
            expect(container.read(healthEventsProvider).first.detail, 'attempt 1');
          });

          test('appending 1001 events caps at 1000 and drops oldest', () {
            final notifier = container.read(healthEventsProvider.notifier);
            for (var i = 0; i < 1001; i++) {
              notifier.record(_evt(i));
            }
            final events = container.read(healthEventsProvider);
            expect(events.length, 1000);
            // oldest (i=0) dropped; first now i=1
            expect(events.first.detail, 'attempt 1');
            expect(events.last.detail, 'attempt 1000');
          });

          test('clear empties the list', () {
            final notifier = container.read(healthEventsProvider.notifier);
            notifier.record(_evt(1));
            notifier.record(_evt(2));
            notifier.clear();
            expect(container.read(healthEventsProvider), isEmpty);
          });
        });
      }
      ```

    Step G — test/features/monitoring/reconnect/ stubs (4 files, per VALIDATION.md Wave 0):
      Each stub contains a single placeholder test so the file compiles. Real assertions land in Task 2.

      test/features/monitoring/reconnect/backoff_test.dart:
      ```dart
      import 'package:flutter_test/flutter_test.dart';

      void main() {
        group('computeBackoff', () {
          test('scaffold (filled in Task 2)', () {});
        });
      }
      ```

      test/features/monitoring/reconnect/trigger_dedupe_test.dart:
      ```dart
      import 'package:flutter_test/flutter_test.dart';

      void main() {
        group('ReconnectSupervisor dedupe', () {
          test('scaffold (filled in Task 2)', () {});
        });
      }
      ```

      test/features/monitoring/reconnect/state_machine_test.dart:
      ```dart
      import 'package:flutter_test/flutter_test.dart';

      void main() {
        group('ReconnectSupervisor state machine', () {
          test('scaffold (filled in Task 2)', () {});
        });
      }
      ```

      test/features/monitoring/reconnect/defensive_recovery_test.dart:
      ```dart
      import 'package:flutter_test/flutter_test.dart';

      void main() {
        group('ReconnectSupervisor defensive recovery', () {
          test('scaffold (filled in Task 2)', () {});
        });
      }
      ```

    Step H — verify compilation:
      Run `flutter analyze lib test` — must exit 0.
      Run `flutter test test/features/monitoring/` — must exit 0 (stubs pass trivially; real assertions in Task 2).
  </action>
  <verify>
    <automated>flutter pub get &amp;&amp; flutter analyze --no-preamble lib test &amp;&amp; flutter test --reporter expanded test/features/monitoring/models/player_state_test.dart test/features/monitoring/health/event_stream_cap_test.dart</automated>
  </verify>
  <acceptance_criteria>
    - `grep -E "^\s+connectivity_plus: \^7\.1\.1" pubspec.yaml` exits 0
    - `grep -E "^\s+flutter_local_notifications: \^19\.0\.0" pubspec.yaml` exits 0
    - `grep -E "^\s+fake_async: \^1\.3\.0" pubspec.yaml` exits 0
    - `grep -E "enum CameraConnectionStatus \{ idle, connecting, playing, reconnecting, error \}" lib/features/monitoring/models/player_state.dart` exits 0
    - `grep "bool get isReconnecting" lib/features/monitoring/models/player_state.dart` exits 0
    - `test -f lib/features/monitoring/models/health_event.dart` and `grep "enum HealthEventType" lib/features/monitoring/models/health_event.dart` exits 0
    - `grep -E "monitoringStarted,\s*$" lib/features/monitoring/models/health_event.dart` and similarly for all 10 event types (monitoringStarted, monitoringStopped, streamStarted, streamError, reconnectAttempt, reconnectSuccess, zombieDetected, wifiDropped, wifiReconnected, alertFired) each exit 0
    - `test -f lib/features/monitoring/providers/health_events_provider.dart` and `grep "class HealthEventsNotifier extends Notifier<List<HealthEvent>>" lib/features/monitoring/providers/health_events_provider.dart` exits 0
    - `grep "static const _maxEvents = 1000" lib/features/monitoring/providers/health_events_provider.dart` exits 0
    - `grep "final healthEventsProvider = NotifierProvider<HealthEventsNotifier" lib/features/monitoring/providers/health_events_provider.dart` exits 0
    - All 6 test files exist: `for f in test/features/monitoring/models/player_state_test.dart test/features/monitoring/health/event_stream_cap_test.dart test/features/monitoring/reconnect/backoff_test.dart test/features/monitoring/reconnect/trigger_dedupe_test.dart test/features/monitoring/reconnect/state_machine_test.dart test/features/monitoring/reconnect/defensive_recovery_test.dart; do test -f "$f" || exit 1; done`
    - `flutter analyze --no-preamble lib test` exits 0 (zero issues)
    - `flutter test test/features/monitoring/models/player_state_test.dart test/features/monitoring/health/event_stream_cap_test.dart` exits 0 (all 8+ tests green)
  </acceptance_criteria>
  <done>
    Dependencies pinned correctly, enum expanded, HealthEvent model + HealthEventsNotifier exist with 1000-cap and clear() logic, test scaffolds in place for Wave 0, and the codebase still analyzes+tests clean.
  </done>
</task>

<task type="auto" tdd="true">
  <name>Task 2: ReconnectSupervisor service — backoff math, dedup, retry-forever timer, session teardown</name>
  <files>
    lib/features/monitoring/services/reconnect_supervisor.dart,
    test/features/monitoring/reconnect/backoff_test.dart,
    test/features/monitoring/reconnect/trigger_dedupe_test.dart,
    test/features/monitoring/reconnect/state_machine_test.dart,
    test/features/monitoring/reconnect/defensive_recovery_test.dart
  </files>
  <read_first>
    - .planning/phases/04-reliability-overnight-monitoring/04-PATTERNS.md §4 (ReconnectSupervisor — verbatim patterns for _ReconnectState, Pattern 3 dedup, Pattern 4 triple-layer defensive timer, cancelAll)
    - .planning/phases/04-reliability-overnight-monitoring/04-RESEARCH.md §Pattern 2 (computeBackoff — 1<<attempt.clamp(0,5), cap 30, ±20% jitter), §Pattern 4 (defensive recurring timer), §Section 5 (state machine design, cancellation, reconnect cause propagation), §Section 2 (player.open reuse + 15s timeout wrap + mpv property reset hedge)
    - .planning/phases/04-reliability-overnight-monitoring/04-CONTEXT.md §decisions D-01, D-02, D-03 (triggers a only for this plan), D-04 (alert timer fields only — firing logic in Plan 04), D-15 (emit reconnect events)
    - CLAUDE.md §Conventions > Defensive error handling (THREE-LAYER try/catch non-negotiable)
    - lib/features/monitoring/providers/audio_player_provider.dart lines 21–44 (map + subscriptions + onDispose pattern), 100–104 (stream.error existing listener), 220–265 (initial open with setProperty block — to be extracted to _applyPlaybackTuning helper on Task 3)
    - lib/features/monitoring/models/player_state.dart (enum — now has reconnecting after Task 1)
    - lib/features/monitoring/models/health_event.dart (created in Task 1)
    - lib/features/monitoring/providers/health_events_provider.dart (created in Task 1)
    - Existing test/features/monitoring/audio_player_provider_test.dart for Flutter test conventions already in use
  </read_first>
  <behavior>
    - Backoff math (D-01): attempt 0 → base 1s; attempt 1 → 2s; 2 → 4s; 3 → 8s; 4 → 16s; 5 → 30s (capped); 6 → 30s; 99 → 30s. Jitter ±20% applied.
    - Jitter bounds (D-01): 100 samples at attempt 3 (base 8000ms): every result in [6400, 9600] ms inclusive.
    - Dedup (Pattern 3): two `requestReconnect` calls for the same cameraId while inFlight=true → exactly one reconnect attempt runs; second call is logged and suppressed.
    - Retry-forever (D-02 + Pattern 4): if `_attemptReconnect` throws, `_scheduleRetry` MUST schedule the next attempt with incremented backoff. Test simulates 5 consecutive failures and asserts 5 scheduled retries with correctly increasing delays.
    - State-machine: on reconnect kickoff, supervisor calls a callback (`onStatusChange(cameraId, reconnecting)`); on success, it calls `onStatusChange(cameraId, playing)` and resets attempt to 0. Test asserts transitions are emitted in order.
    - Defensive recovery: an exception thrown inside `onAttempt` (the attempt callback) MUST NOT kill the supervisor — the next retry is still scheduled. Test uses a counter to prove ≥2 attempts happen even when the first throws.
    - cancelAll: calling `cancelAll()` cancels every retryTimer + alertTimer and clears `_perCamera`. Test asserts pending timers do NOT fire after cancelAll.
  </behavior>
  <action>
    Step A — Create lib/features/monitoring/services/reconnect_supervisor.dart (per PATTERNS.md §4 + RESEARCH §Section 5):

    ```dart
    import 'dart:async';
    import 'dart:math';

    import '../../../core/logging/app_logger.dart';

    /// Per-camera operational state held by the supervisor.
    /// NOT part of UI state — `CameraAudioState` stays minimal.
    class _ReconnectState {
      int attempt = 0;                   // current backoff attempt (0 = first attempt)
      Timer? retryTimer;                 // scheduled next retry
      Timer? alertTimer;                 // 5-min alert countdown (set by Plan 04)
      bool alertFired = false;           // one-shot gate (D-04; enforced by Plan 04)
      bool inFlight = false;             // dedupe guard (Pattern 3)
      DateTime? firstDropAt;             // for health summary downtime
    }

    /// D-01 exponential backoff with ±20% jitter, capped at 30s.
    /// Attempts 0..5 yield 1,2,4,8,16,30 (pre-jitter); attempt>=5 stays at 30.
    Duration computeBackoff(int attempt, {Random? random}) {
      final r = random ?? Random();
      final clamped = attempt.clamp(0, 5);
      final base = 1 << clamped;            // 1,2,4,8,16,32
      final capped = base > 30 ? 30 : base; // 1,2,4,8,16,30
      final jitter = 1.0 + (r.nextDouble() - 0.5) * 0.4; // [0.8, 1.2]
      final ms = (capped * 1000 * jitter).round();
      return Duration(milliseconds: ms);
    }

    /// D-01/D-02: per-camera reconnect supervisor.
    /// - Exponential backoff with ±20% jitter (computeBackoff)
    /// - Retry forever — never stops scheduling on its own
    /// - Dedups overlapping triggers via inFlight guard (Pattern 3)
    /// - Three-layer defensive try/catch so timer exceptions NEVER kill the loop
    ///
    /// Integration:
    /// - `onAttempt(cameraId)` is the caller-provided reconnect action
    ///   (typically: player.stop() + _applyPlaybackTuning() + player.open()).
    ///   It MAY throw; supervisor schedules the next attempt on failure.
    /// - `onStatusChange(cameraId, reconnecting|playing)` lets the caller
    ///   flip UI state via the existing `copyWithCamera` pattern.
    /// - `onEvent(type, cameraId, detail)` emits health events
    ///   (typically forwards to healthEventsProvider.notifier.record).
    class ReconnectSupervisor {
      ReconnectSupervisor({
        required this.onAttempt,
        required this.onStatusChange,
        required this.onEvent,
        Random? random,
      }) : _random = random ?? Random();

      final Future<void> Function(String cameraId) onAttempt;
      final void Function(String cameraId, ReconnectStatus status) onStatusChange;
      final void Function(ReconnectEventType type, String cameraId, String? detail) onEvent;
      final Random _random;
      final Map<String, _ReconnectState> _perCamera = {};

      /// Dedup-protected entry point (D-03 triggers all route here).
      /// Schedules a retry with computed backoff unless one is already in-flight.
      Future<void> requestReconnect(
        String cameraId, {
        required String cause,
        bool immediate = false,
      }) async {
        final st = _perCamera.putIfAbsent(cameraId, () => _ReconnectState());
        if (st.inFlight) {
          appLog('RECONNECT', '$cameraId: suppressed duplicate ($cause)');
          return;
        }
        st.inFlight = true;
        st.firstDropAt ??= DateTime.now();
        onStatusChange(cameraId, ReconnectStatus.reconnecting);
        onEvent(ReconnectEventType.reconnectAttempt, cameraId, 'attempt ${st.attempt} (cause=$cause)');

        try {
          if (immediate) {
            // WiFi-reconnect trigger (D-03): bypass backoff — network just came back.
            st.retryTimer?.cancel();
            await _attemptReconnect(cameraId);
          } else {
            _scheduleRetry(cameraId, computeBackoff(st.attempt, random: _random));
          }
        } finally {
          st.inFlight = false;
        }
      }

      /// THREE-LAYER defensive recurring timer (Pattern 4, CLAUDE.md §Conventions).
      /// Inner try/catch recovers from attempt failures.
      /// Outer try/catch protects the scheduling call itself (D-02 retry-forever).
      void _scheduleRetry(String cameraId, Duration delay) {
        final st = _perCamera.putIfAbsent(cameraId, () => _ReconnectState());
        st.retryTimer?.cancel();
        appLog('RECONNECT', '$cameraId: scheduling retry in ${delay.inMilliseconds}ms (attempt=${st.attempt})');
        st.retryTimer = Timer(delay, () async {
          try {
            await _attemptReconnect(cameraId);
          } catch (e, stack) {
            appLog('RECONNECT', '$cameraId: retry crashed: $e\n$stack');
            // D-02: retry forever. Schedule the NEXT attempt even after a crash.
            try {
              st.attempt += 1;
              _scheduleRetry(cameraId, computeBackoff(st.attempt, random: _random));
            } catch (_) {
              // Double-catch: if scheduling itself throws, stream.error listener
              // will kick the supervisor again via requestReconnect. Loop MUST NOT die.
              appLog('RECONNECT', '$cameraId: scheduling itself failed — relying on stream.error fallback');
            }
          }
        });
      }

      Future<void> _attemptReconnect(String cameraId) async {
        final st = _perCamera.putIfAbsent(cameraId, () => _ReconnectState());
        try {
          await onAttempt(cameraId);
          // Success: reset backoff, record recovery.
          st.attempt = 0;
          st.firstDropAt = null;
          onStatusChange(cameraId, ReconnectStatus.playing);
          onEvent(ReconnectEventType.reconnectSuccess, cameraId, null);
          appLog('RECONNECT', '$cameraId: reconnect succeeded');
        } catch (e) {
          // Failure: increment attempt and schedule the next retry (D-02).
          st.attempt += 1;
          appLog('RECONNECT', '$cameraId: attempt failed ($e), scheduling next');
          _scheduleRetry(cameraId, computeBackoff(st.attempt, random: _random));
          rethrow; // Let outer try/catch in _scheduleRetry log the stack too.
        }
      }

      /// Cancel all timers (retry + alert) and forget all per-camera state.
      /// MUST be called from stopMonitoring AND onDispose.
      void cancelAll() {
        for (final st in _perCamera.values) {
          st.retryTimer?.cancel();
          st.alertTimer?.cancel();
        }
        _perCamera.clear();
        appLog('RECONNECT', 'Supervisor cancelled all timers');
      }

      /// Test hook: inspect pending retry state.
      int attemptCount(String cameraId) => _perCamera[cameraId]?.attempt ?? 0;
      bool hasPendingRetry(String cameraId) =>
          (_perCamera[cameraId]?.retryTimer?.isActive ?? false);
    }

    /// Supervisor-facing status signals. The caller maps these to
    /// CameraConnectionStatus (reconnecting / playing) via onStatusChange.
    enum ReconnectStatus { reconnecting, playing }

    /// Supervisor-facing event signals. The caller maps these to
    /// HealthEventType (reconnectAttempt / reconnectSuccess) via onEvent.
    enum ReconnectEventType { reconnectAttempt, reconnectSuccess }
    ```

    Step B — Flesh out test/features/monitoring/reconnect/backoff_test.dart:

    ```dart
    import 'dart:math';

    import 'package:flutter_test/flutter_test.dart';
    import 'package:rtsp_mixer/features/monitoring/services/reconnect_supervisor.dart';

    void main() {
      group('computeBackoff (D-01 exponential + ±20% jitter, cap 30s)', () {
        test('attempt 0 with zero-jitter random is ~1000ms', () {
          final r = _FixedRandom(0.5); // nextDouble -> 0.5 => jitter factor 1.0
          final d = computeBackoff(0, random: r);
          expect(d.inMilliseconds, 1000);
        });

        test('progression 0..5 is 1, 2, 4, 8, 16, 30 seconds (pre-jitter center)', () {
          final r = _FixedRandom(0.5);
          expect(computeBackoff(0, random: r).inMilliseconds, 1000);
          expect(computeBackoff(1, random: r).inMilliseconds, 2000);
          expect(computeBackoff(2, random: r).inMilliseconds, 4000);
          expect(computeBackoff(3, random: r).inMilliseconds, 8000);
          expect(computeBackoff(4, random: r).inMilliseconds, 16000);
          expect(computeBackoff(5, random: r).inMilliseconds, 30000);
        });

        test('attempt >= 5 is capped at 30s (not 32s, not 64s)', () {
          final r = _FixedRandom(0.5);
          expect(computeBackoff(6, random: r).inMilliseconds, 30000);
          expect(computeBackoff(10, random: r).inMilliseconds, 30000);
          expect(computeBackoff(99, random: r).inMilliseconds, 30000);
        });

        test('100 samples at attempt 3 (base 8s) stay within ±20% jitter [6400, 9600] ms', () {
          final rng = Random(42);
          for (var i = 0; i < 100; i++) {
            final d = computeBackoff(3, random: rng);
            expect(d.inMilliseconds, greaterThanOrEqualTo(6400));
            expect(d.inMilliseconds, lessThanOrEqualTo(9600));
          }
        });
      });
    }

    /// Deterministic Random for tests — always returns the constant.
    class _FixedRandom implements Random {
      _FixedRandom(this.value);
      final double value;
      @override double nextDouble() => value;
      @override int nextInt(int max) => 0;
      @override bool nextBool() => false;
    }
    ```

    Step C — Flesh out test/features/monitoring/reconnect/trigger_dedupe_test.dart:

    ```dart
    import 'package:fake_async/fake_async.dart';
    import 'package:flutter_test/flutter_test.dart';
    import 'package:rtsp_mixer/features/monitoring/services/reconnect_supervisor.dart';

    void main() {
      group('ReconnectSupervisor dedupe (Pattern 3)', () {
        test('two simultaneous requests for the same camera produce one attempt', () {
          fakeAsync((async) {
            var attempts = 0;
            final sup = ReconnectSupervisor(
              onAttempt: (_) async => attempts++,
              onStatusChange: (_, __) {},
              onEvent: (_, __, ___) {},
            );
            // First call enters, schedules. Second is suppressed while inFlight.
            sup.requestReconnect('cam1', cause: 'player_error');
            sup.requestReconnect('cam1', cause: 'zombie');
            async.elapse(const Duration(seconds: 2));
            expect(attempts, 1);
          });
        });

        test('different cameras do NOT dedupe each other', () {
          fakeAsync((async) {
            var attemptsCam1 = 0;
            var attemptsCam2 = 0;
            final sup = ReconnectSupervisor(
              onAttempt: (id) async =>
                  id == 'cam1' ? attemptsCam1++ : attemptsCam2++,
              onStatusChange: (_, __) {},
              onEvent: (_, __, ___) {},
            );
            sup.requestReconnect('cam1', cause: 'player_error');
            sup.requestReconnect('cam2', cause: 'player_error');
            async.elapse(const Duration(seconds: 2));
            expect(attemptsCam1, 1);
            expect(attemptsCam2, 1);
          });
        });
      });
    }
    ```

    Step D — Flesh out test/features/monitoring/reconnect/state_machine_test.dart:

    ```dart
    import 'package:fake_async/fake_async.dart';
    import 'package:flutter_test/flutter_test.dart';
    import 'package:rtsp_mixer/features/monitoring/services/reconnect_supervisor.dart';

    void main() {
      group('ReconnectSupervisor state machine (RELY-02 transitions)', () {
        test('successful reconnect emits reconnecting -> playing and resets attempt', () {
          fakeAsync((async) {
            final statuses = <ReconnectStatus>[];
            final events = <ReconnectEventType>[];
            final sup = ReconnectSupervisor(
              onAttempt: (_) async {}, // success
              onStatusChange: (_, s) => statuses.add(s),
              onEvent: (t, _, __) => events.add(t),
            );
            sup.requestReconnect('cam1', cause: 'player_error');
            async.elapse(const Duration(seconds: 2));
            expect(statuses, [ReconnectStatus.reconnecting, ReconnectStatus.playing]);
            expect(events, [
              ReconnectEventType.reconnectAttempt,
              ReconnectEventType.reconnectSuccess,
            ]);
            expect(sup.attemptCount('cam1'), 0);
          });
        });

        test('cancelAll cancels pending retryTimers (no attempts fire after cancel)', () {
          fakeAsync((async) {
            var attempts = 0;
            final sup = ReconnectSupervisor(
              onAttempt: (_) async {
                attempts++;
                throw StateError('fail'); // force re-schedule
              },
              onStatusChange: (_, __) {},
              onEvent: (_, __, ___) {},
            );
            sup.requestReconnect('cam1', cause: 'player_error');
            async.elapse(const Duration(seconds: 2)); // attempt 0 fires
            expect(attempts, 1);
            sup.cancelAll();
            async.elapse(const Duration(seconds: 120)); // should NOT fire again
            expect(attempts, 1);
            expect(sup.hasPendingRetry('cam1'), false);
          });
        });
      });
    }
    ```

    Step E — Flesh out test/features/monitoring/reconnect/defensive_recovery_test.dart:

    ```dart
    import 'package:fake_async/fake_async.dart';
    import 'package:flutter_test/flutter_test.dart';
    import 'package:rtsp_mixer/features/monitoring/services/reconnect_supervisor.dart';

    void main() {
      group('ReconnectSupervisor retry-forever + defensive recovery (D-02)', () {
        test('5 consecutive failures still schedule a 6th attempt', () {
          fakeAsync((async) {
            var attempts = 0;
            final sup = ReconnectSupervisor(
              onAttempt: (_) async {
                attempts++;
                throw StateError('simulated failure $attempts');
              },
              onStatusChange: (_, __) {},
              onEvent: (_, __, ___) {},
            );
            sup.requestReconnect('cam1', cause: 'player_error');
            async.elapse(const Duration(seconds: 2));   // attempt 0 (~1s)
            async.elapse(const Duration(seconds: 3));   // attempt 1 (~2s)
            async.elapse(const Duration(seconds: 5));   // attempt 2 (~4s)
            async.elapse(const Duration(seconds: 9));   // attempt 3 (~8s)
            async.elapse(const Duration(seconds: 17));  // attempt 4 (~16s)
            expect(attempts, greaterThanOrEqualTo(5));
            expect(sup.hasPendingRetry('cam1'), true);
          });
        });

        test('an exception inside onAttempt callback does NOT kill the loop', () {
          fakeAsync((async) {
            var attempts = 0;
            final sup = ReconnectSupervisor(
              onAttempt: (_) async {
                attempts++;
                // First two throw, rest succeed.
                if (attempts <= 2) throw Exception('boom $attempts');
              },
              onStatusChange: (_, __) {},
              onEvent: (_, __, ___) {},
            );
            sup.requestReconnect('cam1', cause: 'player_error');
            async.elapse(const Duration(seconds: 10));
            expect(attempts, greaterThanOrEqualTo(3));
            expect(sup.attemptCount('cam1'), 0); // reset after success
          });
        });
      });
    }
    ```

    Step F — Ensure imports: pubspec.yaml already has `fake_async` from Task 1; `mockito` already present. Run `flutter pub get` if not yet invoked.

    Step G — Verify:
      Run `flutter analyze --no-preamble lib test` — zero issues.
      Run `flutter test test/features/monitoring/reconnect/` — all tests green.
  </action>
  <verify>
    <automated>flutter analyze --no-preamble lib test &amp;&amp; flutter test --reporter expanded test/features/monitoring/reconnect/</automated>
  </verify>
  <acceptance_criteria>
    - `test -f lib/features/monitoring/services/reconnect_supervisor.dart` exits 0
    - `grep "class ReconnectSupervisor" lib/features/monitoring/services/reconnect_supervisor.dart` exits 0
    - `grep "Duration computeBackoff(int attempt" lib/features/monitoring/services/reconnect_supervisor.dart` exits 0
    - `grep "Future<void> requestReconnect" lib/features/monitoring/services/reconnect_supervisor.dart` exits 0
    - `grep "void cancelAll()" lib/features/monitoring/services/reconnect_supervisor.dart` exits 0
    - `grep "enum ReconnectStatus { reconnecting, playing }" lib/features/monitoring/services/reconnect_supervisor.dart` exits 0
    - `grep "enum ReconnectEventType { reconnectAttempt, reconnectSuccess }" lib/features/monitoring/services/reconnect_supervisor.dart` exits 0
    - `grep -c "try {" lib/features/monitoring/services/reconnect_supervisor.dart` reports >= 3 (three-layer defensive pattern)
    - `flutter analyze --no-preamble lib test` exits 0
    - `flutter test test/features/monitoring/reconnect/backoff_test.dart` passes all 4 groups of assertions
    - `flutter test test/features/monitoring/reconnect/trigger_dedupe_test.dart` passes (dedup asserts 1 attempt for same camera)
    - `flutter test test/features/monitoring/reconnect/state_machine_test.dart` passes (reconnecting -> playing, cancelAll stops timers)
    - `flutter test test/features/monitoring/reconnect/defensive_recovery_test.dart` passes (attempts >= 5 and exception does not kill loop)
  </acceptance_criteria>
  <done>
    ReconnectSupervisor exists, compiles, and has full unit coverage for backoff math, jitter bounds, dedup, retry-forever, cancelAll, and three-layer defensive exception recovery. No wiring to AudioPlayerNotifier yet — that is Task 3.
  </done>
</task>

<task type="auto" tdd="true">
  <name>Task 3: Wire ReconnectSupervisor + HealthEvents into AudioPlayerNotifier (player-event triggers, session lifecycle, notification text)</name>
  <files>
    lib/features/monitoring/providers/audio_player_provider.dart
  </files>
  <read_first>
    - .planning/phases/04-reliability-overnight-monitoring/04-PATTERNS.md §8 (audio_player_provider.dart modifications — verbatim), §Shared Patterns (defensive try/catch, appLog tags)
    - .planning/phases/04-reliability-overnight-monitoring/04-RESEARCH.md §Section 10 (integration points, file:line), §Section 2 (_applyPlaybackTuning hedge + 15s open timeout), §Pitfall 1 (uncaught exception kills loop), §Pitfall 3 (mpv properties reset on open)
    - .planning/phases/04-reliability-overnight-monitoring/04-CONTEXT.md §decisions D-03 (triggers a: player error + completed), D-13 (clear events on start, emit monitoringStarted/Stopped), D-15 (streamStarted/streamError events)
    - CLAUDE.md §Conventions > Defensive error handling
    - lib/features/monitoring/providers/audio_player_provider.dart (ENTIRE FILE — you are modifying it; read lines 1–687 to understand current lifecycle, subscriptions, stopMonitoring teardown, notification text building)
    - lib/features/monitoring/services/reconnect_supervisor.dart (created in Task 2 — supervisor contract)
    - lib/features/monitoring/providers/health_events_provider.dart (created in Task 1)
    - lib/features/monitoring/models/health_event.dart (created in Task 1)
  </read_first>
  <behavior>
    - On `startMonitoring`: health events list is cleared (`clear()`), a `monitoringStarted` event is recorded with `detail: '{N} cameras'`. Per-camera `streamStarted` event is recorded for each camera that reaches `playing` initially.
    - On `player.stream.error` listener: a `streamError` event is recorded AND `_reconnectSupervisor.requestReconnect(cameraId, cause: 'player_error')` is called (D-03 trigger a).
    - On `player.stream.completed` listener: a `streamError` event is recorded (completed on an RTSP source = drop per RESEARCH §1 mode 11) AND supervisor.requestReconnect(cause: 'player_completed') is called.
    - Supervisor's `onAttempt` callback: calls `player.stop()` → `await Future.delayed(200ms)` → re-applies all tuning properties via `_applyPlaybackTuning()` → wraps `player.open(Media(activeStreamUrl))` in a 15s timeout → on success re-sets `vid=no` (if video preview is off). Per RESEARCH §Section 2 + Pitfall 3.
    - Supervisor's `onStatusChange` callback: updates CameraAudioState.connectionStatus to `reconnecting` or `playing` via `copyWithCamera` + `copyWith`.
    - Supervisor's `onEvent` callback: forwards to `ref.read(healthEventsProvider.notifier).record(HealthEvent(...))` with correct HealthEventType mapping (reconnectAttempt, reconnectSuccess).
    - On `stopMonitoring`: `_reconnectSupervisor.cancelAll()` is called BEFORE cancelling subscriptions and disposing players; `monitoringStopped` event is recorded last.
    - Notification text builder: strings like `"Monitoring: Nursery (reconnecting), Bedroom"` pass through naturally — the enum's `.name` accessor renders `reconnecting` correctly, no change needed beyond ensuring the fallback still reads it.
  </behavior>
  <action>
    Step A — Add imports at top of audio_player_provider.dart (after existing imports):
    ```dart
    import '../models/health_event.dart';
    import '../services/reconnect_supervisor.dart';
    import 'health_events_provider.dart';
    ```

    Step B — Add a supervisor field and tuning-helper to AudioPlayerNotifier class (near other fields, after `_lastNotificationText` declaration):
    ```dart
    late final ReconnectSupervisor _reconnectSupervisor = ReconnectSupervisor(
      onAttempt: _performReconnectOpen,
      onStatusChange: _applyReconnectStatus,
      onEvent: _recordReconnectEvent,
    );
    ```

    Step C — Extract the `setProperty` tuning block from current `startMonitoring` (lines 228–237 in existing code) into a new private helper method at class level (it will be reused for both initial open and every reconnect — per RESEARCH §Pitfall 3):
    ```dart
    /// Apply all mpv tuning properties. Idempotent; safe to call before every open().
    /// Hedge against Pitfall 3 (RESEARCH §Pitfall 3) — properties may reset across open().
    Future<void> _applyPlaybackTuning(NativePlayer nativePlayer) async {
      final settings = ref.read(settingsProvider);
      await nativePlayer.setProperty('demuxer-lavf-o', 'rtsp_transport=tcp');
      await nativePlayer.setProperty('cache', 'yes');
      await nativePlayer.setProperty('demuxer-max-bytes', '512KiB');
      await nativePlayer.setProperty('demuxer-readahead-secs', '2');
      await nativePlayer.setProperty('cache-pause', 'no');
      await nativePlayer.setProperty('audio-buffer', settings.audioBufferSeconds.toString());
    }
    ```
    Replace the inline setProperty block in `startMonitoring` with a single call: `await _applyPlaybackTuning(nativePlayer);`. Keep everything else in that try block identical (VideoController creation, _listenToPlayer call, open, vid=no).

    Step D — Add the three supervisor callbacks as private methods on AudioPlayerNotifier:

    ```dart
    /// Supervisor's onAttempt: actually reconnect the media_kit Player.
    /// Reuses the same Player instance (RESEARCH §Section 2 Pattern 1).
    /// Wraps open() in a 15s timeout (RESEARCH §Section 2 open() timeout behavior).
    Future<void> _performReconnectOpen(String cameraId) async {
      final player = _players[cameraId];
      if (player == null) {
        throw StateError('No player for $cameraId');
      }
      final current = state.value;
      final idx = _cameraIndex(cameraId);
      if (current == null || idx < 0) {
        throw StateError('No camera state for $cameraId');
      }
      final cam = current.cameras[idx];
      final url = cam.activeStreamUrl;
      if (url == null || url.isEmpty) {
        throw StateError('No active stream URL for $cameraId');
      }

      appLog('RECONNECT', '$cameraId: stop + reopen $url');
      try {
        await player.stop();
      } catch (e) {
        appLog('RECONNECT', '$cameraId: stop() failed (continuing): $e');
      }
      await Future.delayed(const Duration(milliseconds: 200));

      final nativePlayer = player.platform as NativePlayer;
      // Re-apply tuning properties — hedge against Pitfall 3 (property reset).
      try {
        await _applyPlaybackTuning(nativePlayer);
      } catch (e) {
        appLog('RECONNECT', '$cameraId: tuning re-apply failed (continuing): $e');
      }

      // Wrap open() in a 15s timeout — mpv network-timeout is broken for RTSP.
      await player.open(Media(url)).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw TimeoutException('player.open($url) exceeded 15s', const Duration(seconds: 15));
        },
      );

      // Re-disable video after open unless preview is on (same rule as startMonitoring).
      try {
        await nativePlayer.setProperty('vid', 'no');
      } catch (e) {
        appLog('RECONNECT', '$cameraId: vid=no failed (non-fatal): $e');
      }
    }

    /// Supervisor's onStatusChange: flip UI state.
    void _applyReconnectStatus(String cameraId, ReconnectStatus status) {
      final current = state.value;
      if (current == null) return;
      final idx = _cameraIndex(cameraId);
      if (idx < 0) return;
      final cam = current.cameras[idx];
      final newStatus = status == ReconnectStatus.reconnecting
          ? CameraConnectionStatus.reconnecting
          : CameraConnectionStatus.playing;
      state = AsyncData(current.copyWithCamera(
        idx,
        cam.copyWith(connectionStatus: newStatus),
      ));
    }

    /// Supervisor's onEvent: record to health summary stream.
    void _recordReconnectEvent(
      ReconnectEventType type,
      String cameraId,
      String? detail,
    ) {
      try {
        final current = state.value;
        final cameraName = current != null
            ? _findCameraName(cameraId) ?? cameraId
            : cameraId;
        final evtType = type == ReconnectEventType.reconnectAttempt
            ? HealthEventType.reconnectAttempt
            : HealthEventType.reconnectSuccess;
        ref.read(healthEventsProvider.notifier).record(HealthEvent(
              timestamp: DateTime.now(),
              type: evtType,
              cameraId: cameraId,
              cameraName: cameraName,
              detail: detail,
            ));
      } catch (e) {
        appLog('RECONNECT', 'Failed to record event: $e');
      }
    }

    String? _findCameraName(String cameraId) {
      final current = state.value;
      if (current == null) return null;
      for (final c in current.cameras) {
        if (c.cameraId == cameraId) return c.cameraName;
      }
      return null;
    }
    ```

    Step E — Extend `_listenToPlayer` (current lines 89–162). Find the existing `player.stream.error` listener (lines 100–104) and extend:
    ```dart
    _subscriptions.add(
      player.stream.error.listen((error) {
        appLog('STREAM', '$cameraName error=$error');
        try {
          final msg = error.toString();
          // UI-SPEC §Event log row copy contract: streamError detail truncated to 80 chars with ellipsis.
          final detail = msg.length > 80 ? '${msg.substring(0, 80)}…' : msg;
          ref.read(healthEventsProvider.notifier).record(HealthEvent(
                timestamp: DateTime.now(),
                type: HealthEventType.streamError,
                cameraId: cameraId,
                cameraName: cameraName,
                detail: detail,
              ));
        } catch (e) {
          appLog('HEALTH', 'Failed to record streamError: $e');
        }
        _reconnectSupervisor.requestReconnect(cameraId, cause: 'player_error');
      }),
    );
    ```

    Find the existing `player.stream.completed` listener (lines 95–99):
    ```dart
    _subscriptions.add(
      player.stream.completed.listen((completed) {
        appLog('STREAM', '$cameraName completed=$completed');
        if (completed) {
          try {
            ref.read(healthEventsProvider.notifier).record(HealthEvent(
                  timestamp: DateTime.now(),
                  type: HealthEventType.streamError,
                  cameraId: cameraId,
                  cameraName: cameraName,
                  detail: 'stream completed (RTSP drop)',
                ));
          } catch (e) {
            appLog('HEALTH', 'Failed to record completed event: $e');
          }
          _reconnectSupervisor.requestReconnect(cameraId, cause: 'player_completed');
        }
      }),
    );
    ```

    Step F — Extend `startMonitoring` (lines 174–310). Near the very top of the method (after `state = const AsyncLoading();` on line 182), add:
    ```dart
    // D-13: session boundary — clear previous session's health events.
    try {
      ref.read(healthEventsProvider.notifier).clear();
      ref.read(healthEventsProvider.notifier).record(HealthEvent(
            timestamp: DateTime.now(),
            type: HealthEventType.monitoringStarted,
            detail: '${selectedCameras.length} cameras',
          ));
    } catch (e) {
      appLog('HEALTH', 'Failed to clear/record monitoringStarted: $e');
    }
    ```

    At the end of the per-camera `try { ... player.open ... camState = camState.copyWith(playing) ...}` block (right after `appLog('AUDIO', '$cameraName is now playing');` — line 258), add:
    ```dart
    try {
      ref.read(healthEventsProvider.notifier).record(HealthEvent(
            timestamp: DateTime.now(),
            type: HealthEventType.streamStarted,
            cameraId: camera.id,
            cameraName: cameraName,
          ));
    } catch (e) {
      appLog('HEALTH', 'Failed to record streamStarted: $e');
    }
    ```

    Step G — Extend `stopMonitoring` (current lines 639–657). Insert `_reconnectSupervisor.cancelAll()` IMMEDIATELY after `_levelPollTimer?.cancel();` (line 641). At the END of the method (after `state = const AsyncData(MonitoringState());` on line 655), record the monitoringStopped event:
    ```dart
    try {
      ref.read(healthEventsProvider.notifier).record(HealthEvent(
            timestamp: DateTime.now(),
            type: HealthEventType.monitoringStopped,
          ));
    } catch (e) {
      appLog('HEALTH', 'Failed to record monitoringStopped: $e');
    }
    ```

    Step H — Verify the `ref.onDispose` block at lines 31–44 also calls `_reconnectSupervisor.cancelAll()` (alongside the existing timer+subscription cleanup). Insert at the start of the onDispose callback:
    ```dart
    try { _reconnectSupervisor.cancelAll(); } catch (_) {}
    ```

    Step I — Notification text: the current `_buildNotificationText` equivalent at lines 294–306 and 420–430 uses `c.connectionStatus == CameraConnectionStatus.playing ? '' : ' (${c.connectionStatus.name})'`. This already renders `reconnecting` correctly as `(reconnecting)` — no code change required here, but VERIFY by reading the two code sites after the edits.

    Step J — Verify:
      Run `flutter analyze --no-preamble lib test` — zero issues.
      Run `flutter test` — all existing tests green (no regression), Task 2's supervisor tests stay green.
  </action>
  <verify>
    <automated>flutter analyze --no-preamble lib test &amp;&amp; flutter test --reporter expanded</automated>
  </verify>
  <acceptance_criteria>
    - `grep "ReconnectSupervisor(" lib/features/monitoring/providers/audio_player_provider.dart` exits 0
    - `grep "_performReconnectOpen" lib/features/monitoring/providers/audio_player_provider.dart` exits 0
    - `grep "_applyReconnectStatus" lib/features/monitoring/providers/audio_player_provider.dart` exits 0
    - `grep "_recordReconnectEvent" lib/features/monitoring/providers/audio_player_provider.dart` exits 0
    - `grep "_applyPlaybackTuning" lib/features/monitoring/providers/audio_player_provider.dart` exits 0
    - `grep "HealthEventType.monitoringStarted" lib/features/monitoring/providers/audio_player_provider.dart` exits 0
    - `grep "HealthEventType.monitoringStopped" lib/features/monitoring/providers/audio_player_provider.dart` exits 0
    - `grep "HealthEventType.streamStarted" lib/features/monitoring/providers/audio_player_provider.dart` exits 0
    - `grep "HealthEventType.streamError" lib/features/monitoring/providers/audio_player_provider.dart` exits 0
    - `grep "_reconnectSupervisor.requestReconnect" lib/features/monitoring/providers/audio_player_provider.dart` exits 0 (at least 2 hits — error + completed listeners)
    - `grep "_reconnectSupervisor.cancelAll" lib/features/monitoring/providers/audio_player_provider.dart` exits 0
    - `grep -E "\.timeout\(\s*const Duration\(seconds: 15\)" lib/features/monitoring/providers/audio_player_provider.dart` exits 0
    - `grep "cause: 'player_error'" lib/features/monitoring/providers/audio_player_provider.dart` exits 0
    - `grep "cause: 'player_completed'" lib/features/monitoring/providers/audio_player_provider.dart` exits 0
    - `grep -E "msg\.length > 80 \? '\\\$\{msg\.substring\(0, 80\)\}…'" lib/features/monitoring/providers/audio_player_provider.dart` exits 0 (streamError detail truncated to 80 chars + ellipsis per UI-SPEC §Event log row copy contract; invariant: rendered detail is always ≤ 81 chars)
    - `flutter analyze --no-preamble lib test` exits 0
    - `flutter test` passes full suite (no regressions)
  </acceptance_criteria>
  <done>
    AudioPlayerNotifier owns a ReconnectSupervisor that is triggered by `player.stream.error` and `player.stream.completed` events, records every lifecycle + stream event to the health summary, re-applies mpv tuning on every reconnect, times out open() at 15s, and tears down cleanly on stopMonitoring and onDispose. Triggers b (zombie) and c (WiFi) come from later plans — their integration points already exist via `_reconnectSupervisor.requestReconnect(cameraId, cause: ...)`.
  </done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| Main isolate ↔ media_kit Player | Untrusted RTSP payload crosses here; error strings may contain server-provided text. Plan logs via appLog + records to health stream — do NOT forward to network. |
| Main isolate ↔ Riverpod state | Health events are in-memory only (D-14) — no cross-process IPC in this plan. |
| AudioPlayerNotifier ↔ Timer (dart:async) | Retry-forever loop must never leak to unhandled-error zone — defensive three-layer try/catch. |

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-04-01 | Spoofing | RTSP error messages forwarded into health events | accept | In-memory-only event stream (D-14), no network sink. `appLog` writes to app-local /tmp path; not exfiltrated. Camera name is from authoritative Protect API, not user input. |
| T-04-02 | Tampering | HealthEventsNotifier state in single-isolate Riverpod container | accept | No IPC surface; no persistence; process-local only. |
| T-04-03 | Repudiation | Reconnect timeline missing or incomplete | mitigate | Dual-sink logging: every event records via `ref.read(healthEventsProvider.notifier).record(...)` AND `appLog('HEALTH', ...)` — two independent consumers (LogScreen + HealthSummaryScreen) prevent silent loss. |
| T-04-04 | Information Disclosure | Error detail strings leaking camera IPs / credentials in health events | mitigate | Error strings come from `player.stream.error` — media_kit-sanitized and do NOT include RTSP credentials. Limit `detail` to `error.toString()` (already redacted by media_kit). No network sink for the health stream. |
| T-04-05 | Denial of Service | Retry-forever loop hammering a degraded Protect NVR during a firmware update | mitigate | D-01 backoff caps at 30s — steady-state is one attempt per camera per 30s. Jitter ±20% avoids thundering-herd when WiFi AP reboot drops both cameras simultaneously. Battery/memory impact analyzed in RESEARCH §Pitfall 8. |
| T-04-06 | Denial of Service | Event list memory growth during reconnect storm | mitigate | 1000-event cap via HealthEventsNotifier.record (D-17). Worst case ~250KB (RESEARCH §Section 6). Oldest-event drop preserves recent history. |
| T-04-07 | Elevation of Privilege | Exception in timer callback kills retry loop → silent monitoring failure at 3am | mitigate | THREE-LAYER defensive pattern (CLAUDE.md §Conventions + Pattern 4): inner try/catch wraps `onAttempt`; outer try/catch wraps scheduling call; fallback relies on stream.error listener re-kicking supervisor. Unit test `defensive_recovery_test.dart` asserts loop survives 2 consecutive thrown exceptions and ≥5 consecutive failures still schedule next attempt. |
| T-04-08 | Tampering | Race between `stopMonitoring` and in-flight reconnect attempting to open a disposed Player | mitigate | `_reconnectSupervisor.cancelAll()` is called BEFORE `player.dispose()` in stopMonitoring (Step G ordering). Inside `_performReconnectOpen`, all `player.stop()` calls are individually try/caught so a disposed-player error does not tear down the supervisor. |
</threat_model>

<verification>
- `flutter pub get` resolves cleanly with connectivity_plus ^7.1.1 + flutter_local_notifications ^19.0.0 + fake_async ^1.3.0
- `flutter analyze --no-preamble lib test` exits 0 — no new lint issues
- `flutter test` exits 0 — existing tests still pass, new tests for enum, health events cap, backoff math, dedup, state-machine transitions, and defensive recovery all green
- Enum ordering: `CameraConnectionStatus.values` matches `[idle, connecting, playing, reconnecting, error]`
- Supervisor integration: at least two sites in audio_player_provider.dart call `_reconnectSupervisor.requestReconnect(...)` with distinct causes (`player_error`, `player_completed`)
- stopMonitoring cancels supervisor before disposing players (ordering matters — see T-04-08)
- Health events flow: `monitoringStarted` is recorded once per start; `streamStarted` per camera; `streamError` on every player.stream.error; `reconnectAttempt`/`reconnectSuccess` via supervisor callbacks; `monitoringStopped` recorded last in stopMonitoring
</verification>

<success_criteria>
- RELY-01 (partial): exponential backoff + retry-forever loop is in place and unit-tested; triggers a (player events) are wired. Triggers b (zombie) and c (WiFi) deferred to later plans.
- RELY-02 (partial): `reconnecting` enum variant exists and `connectionStatus` transitions through it on every supervisor kickoff. UI rendering of the state lands in Plan 04-03.
- Goal-backward truths (from must_haves): all verifiable via grep + `flutter test`.
</success_criteria>

<output>
After completion, create `.planning/phases/04-reliability-overnight-monitoring/04-01-SUMMARY.md` capturing: the supervisor's API surface (constructor params, public methods), the three callback contracts, the _applyPlaybackTuning helper extraction, and any deviations from PATTERNS.md §4 / §8 that required executor judgment.
</output>
