---
phase: quick-260514-siv
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - pubspec.yaml
  - lib/features/monitoring/models/health_event.dart
  - lib/features/monitoring/models/session.dart
  - lib/features/monitoring/services/session_history_repository.dart
  - lib/features/monitoring/providers/session_history_provider.dart
  - lib/features/monitoring/providers/health_events_provider.dart
  - lib/features/monitoring/providers/audio_player_provider.dart
  - lib/features/monitoring/screens/monitoring_screen.dart
  - lib/features/monitoring/screens/health_summary_screen.dart
  - lib/features/monitoring/screens/sessions_list_screen.dart
  - lib/features/monitoring/widgets/stop_monitoring_button.dart
  - lib/features/monitoring/widgets/active_session_bar.dart
  - lib/core/router/app_router.dart
  - lib/core/widgets/main_shell.dart
autonomous: true
requirements:
  - QUICK-260514-SIV
must_haves:
  truths:
    - "After stopping monitoring the just-ended session is still viewable as a finalized session."
    - "After app restart, the last finalized session is still listed in Sessions."
    - "While monitoring is running, switching to Sessions or Logs tab does not stop audio or restart streams."
    - "While monitoring is running and the user is on a non-Monitor tab, a mini-bar above the NavigationBar shows uptime and a tap returns to Monitor."
    - "Calling startMonitoring while a session is already running is a no-op — events are not cleared, streams are not restarted."
    - "Corrupt or missing sessions.json never crashes the app; history degrades to empty."
    - "Stop button is no longer in the bottom area of MonitoringScreen — it is an extended FAB visible only while a session is running."
  artifacts:
    - path: lib/features/monitoring/models/session.dart
      provides: "Session model with id, startedAt, endedAt, events, cameras + toJson/fromJson"
    - path: lib/features/monitoring/services/session_history_repository.dart
      provides: "Read/write sessions.json with atomic rename + corruption tolerance"
    - path: lib/features/monitoring/providers/session_history_provider.dart
      provides: "AsyncNotifierProvider<SessionHistoryNotifier, SessionHistory> with beginSession/recordEvent/endCurrentSession + debounced writes + lifecycle flush"
    - path: lib/features/monitoring/screens/sessions_list_screen.dart
      provides: "/sessions screen listing in-flight + up to 10 finalized sessions"
    - path: lib/features/monitoring/widgets/active_session_bar.dart
      provides: "Mini-bar widget above NavigationBar shown when on non-Monitor tab during active session"
    - path: lib/core/widgets/main_shell.dart
      provides: "ShellRoute scaffold with IndexedStack + NavigationBar + ActiveSessionBar slot"
  key_links:
    - from: lib/features/monitoring/providers/audio_player_provider.dart
      to: lib/features/monitoring/providers/session_history_provider.dart
      via: "startMonitoring -> beginSession, stopMonitoring -> endCurrentSession"
      pattern: "sessionHistoryProvider\\.notifier\\.(beginSession|endCurrentSession)"
    - from: lib/features/monitoring/providers/health_events_provider.dart
      to: lib/features/monitoring/providers/session_history_provider.dart
      via: "record() forwards every event into sessionHistoryProvider.recordEvent"
      pattern: "sessionHistoryProvider\\.notifier\\.recordEvent"
    - from: lib/core/router/app_router.dart
      to: lib/core/widgets/main_shell.dart
      via: "ShellRoute wraps /monitoring, /sessions, /logs"
      pattern: "ShellRoute"
---

<objective>
Add persistent session/night history (up to 10 finalized sessions + 1 in-flight) and rework the post-login UI around a persistent bottom NavigationBar with an active-session mini-bar so the user can browse other tabs while monitoring keeps running.

Purpose:
- Today, the moment a parent taps Stop, every event in this session disappears — making it impossible to review what happened overnight. Sessions are written to disk so they survive both Stop and process death.
- Today, opening Health Summary or Logs unmounts the monitoring UI and the user worries audio stopped. A shell with IndexedStack keeps Monitor mounted across tab switches; a mini-bar reassures the user audio is still live.
- Also fixes a latent bug: `startMonitoring` unconditionally clears events and restarts streams, which under the new ShellRoute (where MonitoringScreen may be re-entered) would silently destroy a running session.

Output:
- New Session model + JSON repository writing to `<appDocumentsDir>/sessions.json` with atomic write and corruption tolerance.
- New `sessionHistoryProvider` (AsyncNotifierProvider) wired into start/stop/record and flushed on lifecycle pause/detach.
- `audio_player_provider.startMonitoring` becomes idempotent.
- ShellRoute + IndexedStack-based main shell with M3 NavigationBar (Monitor / Sessions / Logs), ActiveSessionBar mini-player, and the Stop button promoted to an extended FAB inside MonitoringScreen.
- New `/sessions` list screen and `/sessions/:id` detail route. `HealthSummaryScreen` takes a `Session` parameter and no longer reads from `healthEventsProvider`.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@./CLAUDE.md
@.planning/STATE.md
@lib/core/logging/app_logger.dart
@lib/core/router/app_router.dart
@lib/core/storage/storage_service.dart
@lib/features/monitoring/models/health_event.dart
@lib/features/monitoring/providers/health_events_provider.dart
@lib/features/monitoring/screens/health_summary_screen.dart
@lib/features/monitoring/screens/monitoring_screen.dart
@lib/features/monitoring/widgets/stop_monitoring_button.dart

<interfaces>
<!-- Key contracts the executor needs. Use these directly — no codebase exploration. -->

From lib/features/monitoring/models/health_event.dart (current, no JSON yet):
- enum HealthEventType { monitoringStarted, monitoringStopped, streamStarted, streamError,
  reconnectAttempt, reconnectSuccess, zombieDetected, wifiDropped, wifiReconnected, alertFired }
- class HealthEvent { final DateTime timestamp; final HealthEventType type; final String? cameraId;
  final String? cameraName; final String? detail; }

From lib/features/monitoring/providers/health_events_provider.dart:
- class HealthEventsNotifier extends Notifier<List<HealthEvent>>
  - void record(HealthEvent event)  // caps at 1000, logs via appLog('HEALTH', ...)
  - void clear()
- final healthEventsProvider = NotifierProvider<HealthEventsNotifier, List<HealthEvent>>(...)

From lib/features/auth/providers/auth_provider.dart line 11:
- final storageProvider = Provider((_) => StorageService());   // already exists, reuse

From lib/core/logging/app_logger.dart line 83:
- void appLog(String tag, String message)   // mandatory tag for new code: 'SESSION'

From lib/features/monitoring/providers/audio_player_provider.dart:
- class AudioPlayerNotifier extends AsyncNotifier<MonitoringState>
  - Future<void> startMonitoring({bool videoPreview = false})   // line 289
  - Future<void> stopMonitoring()                                // line 1021
  - In startMonitoring (lines 303–312), today:
      ref.read(healthEventsProvider.notifier).clear();
      ref.read(healthEventsProvider.notifier).record(HealthEvent(... monitoringStarted ...));
  - In stopMonitoring (lines 1061–1068), today:
      ref.read(healthEventsProvider.notifier).record(HealthEvent(... monitoringStopped ...));

From lib/core/router/app_router.dart (current):
- final appRouterProvider = Provider<GoRouter>((ref) { ... });
- Routes today: /login, /cameras, /monitoring, /logs (all flat GoRoute, no shell)
- The redirect already preserves resumeMonitoring -> /monitoring, leave as-is.
</interfaces>
</context>

<tasks>

<task type="auto">
  <name>Task 1: Persistence layer — Session model, JSON on HealthEvent, repository, provider, and wire it into start/stop/record (with idempotency guard)</name>
  <files>
    pubspec.yaml,
    lib/features/monitoring/models/health_event.dart,
    lib/features/monitoring/models/session.dart,
    lib/features/monitoring/services/session_history_repository.dart,
    lib/features/monitoring/providers/session_history_provider.dart,
    lib/features/monitoring/providers/health_events_provider.dart,
    lib/features/monitoring/providers/audio_player_provider.dart
  </files>
  <action>
1. pubspec.yaml: under `dependencies:` add `path_provider: ^2.1.5` (latest 2.x compatible with Flutter 3.27). Do NOT add uuid — use a 12-char random id from `Random.secure()` + base36 hex; keeps dep surface minimal. Run `flutter pub get` as part of verify.

2. lib/features/monitoring/models/health_event.dart: extend the existing class with `Map<String, dynamic> toJson()` and `factory HealthEvent.fromJson(Map<String, dynamic> json)`. `timestamp` is ISO8601 (`timestamp.toIso8601String()` / `DateTime.parse`). `type` uses `type.name` and `HealthEventType.values.byName(json['type'])`. Nullable string fields pass through as nulls. Do NOT change the constructor or other call sites — additive only.

3. lib/features/monitoring/models/session.dart: NEW. Define
   `class Session { final String id; final DateTime startedAt; final DateTime? endedAt; final List<HealthEvent> events; final List<({String id, String name})> cameras; }`.
   Use a record-typed list for `cameras` to match the description; in JSON serialize as `[{"id":..., "name":...}]`. Provide `Session.start({required cameras})` factory generating id via `Random.secure()` + 12 base36 chars, `startedAt: DateTime.now()`, `endedAt: null`, `events: []`. Provide `Session ended({DateTime? at})` returning a copy with `endedAt`. Provide `Session withEventAppended(HealthEvent e)`. Provide `toJson` / `fromJson` with corrupt-field tolerance (default missing list fields to `[]`, drop events that fail to parse rather than throwing).

4. lib/features/monitoring/services/session_history_repository.dart: NEW. Class `SessionHistoryRepository` with:
   - `Future<({Session? current, List<Session> past})> load()` — reads `<appDocumentsDir>/sessions.json` via `path_provider`. Returns empty on FileNotFoundError, FormatException, or any IOException, logging via `appLog('SESSION', ...)`. Parses `{ "current": Session|null, "past": [Session...] }`. Trims `past` to last 10 if longer.
   - `Future<void> save({Session? current, required List<Session> past})` — atomic write: write to `sessions.json.tmp`, then `await File(tmp).rename(target)`. Wrap in try/catch; on failure log and swallow (must not propagate per CLAUDE.md "no exception may kill a running audio stream"). Trim `past` to 10 before writing.
   Inject `Directory` only via `getApplicationDocumentsDirectory()` — no constructor params needed.

5. lib/features/monitoring/providers/session_history_provider.dart: NEW. Define
   `class SessionHistory { final Session? current; final List<Session> past; const SessionHistory({this.current, this.past = const []}); }`.
   Define `class SessionHistoryNotifier extends AsyncNotifier<SessionHistory>` with:
   - `Future<SessionHistory> build()` — loads from repository, registers a dispose-time flush via `ref.onDispose`, and returns initial state.
   - `Future<void> beginSession(List<({String id, String name})> cameras)` — if `state.value?.current != null` log and noop (defense in depth); else create new Session.start and update state. Schedule debounced write.
   - `void recordEvent(HealthEvent e)` — if `current == null` log and noop; else append to current.events and schedule debounced write.
   - `Future<void> endCurrentSession()` — if `current == null` noop; else move current to head of past (trim past to 10), set current=null, AWAIT a synchronous flush (cancel any pending debounce).
   - `Future<void> flush()` — cancel pending debounce timer and call `repository.save(...)`.
   - Internal Timer-based 1s debounce. All file IO wrapped in try/catch with `appLog('SESSION', ...)`.
   Provider: `final sessionHistoryProvider = AsyncNotifierProvider<SessionHistoryNotifier, SessionHistory>(SessionHistoryNotifier.new);`
   Also register a top-level `WidgetsBindingObserver` in `build()` — on `AppLifecycleState.paused` or `detached`, call `flush()`. Add the observer in `build()` and remove on `ref.onDispose`.

6. lib/features/monitoring/providers/health_events_provider.dart: in `record(HealthEvent event)`, after the existing `state = updated;` + `appLog('HEALTH', ...)`, also call `ref.read(sessionHistoryProvider.notifier).recordEvent(event);` wrapped in try/catch with `appLog('SESSION', 'forward failed: $e')`. Decision rationale to include in code comment: "forwarding chosen over derived-state to keep blast radius small — healthEventsProvider remains the in-memory UI source of truth this session, sessionHistoryProvider owns persistence." Convert `HealthEventsNotifier` from `Notifier` to `Notifier` (no change), but it needs `ref` access — already inherited.

7. lib/features/monitoring/providers/audio_player_provider.dart:
   - At the top of `startMonitoring` (line 289 area, BEFORE `state = const AsyncLoading();` and BEFORE the existing healthEventsProvider.clear() block at 303–312), add an idempotency guard:
     ```
     final existing = ref.read(sessionHistoryProvider).value?.current;
     final running = state.value?.cameras.any((c) =>
         c.connectionStatus == CameraConnectionStatus.connecting ||
         c.connectionStatus == CameraConnectionStatus.connected) ?? false;
     if (existing != null && running) {
       appLog('AUDIO', 'startMonitoring called while session already in progress — noop');
       return;
     }
     ```
     (NOTE: do not put this fenced block in a separate file — it is the new prologue inside startMonitoring. Quoted here for clarity only.)
   - Immediately after the existing `healthEventsProvider.notifier.clear()` + record(monitoringStarted) block at lines 303–312, call:
     `ref.read(sessionHistoryProvider.notifier).beginSession(selectedCameras.map((c) => (id: c.id, name: c.name ?? 'Camera')).toList());`
     wrapped in try/catch with appLog('SESSION', ...).
   - At the end of `stopMonitoring` (line 1069 area, AFTER the existing record(monitoringStopped) block at 1061–1068), call:
     `await ref.read(sessionHistoryProvider.notifier).endCurrentSession();`
     wrapped in try/catch with appLog('SESSION', ...).
  </action>
  <verify>
    <automated>cd /Users/fvoska/projects/personal/rtsp-audio-mixer && flutter pub get && flutter analyze lib/features/monitoring lib/core 2>&1 | tee /tmp/analyze.log && grep -E "error •" /tmp/analyze.log | grep -v "^$" | wc -l | awk '{exit ($1 > 0)}'</automated>
  </verify>
  <done>
- `flutter pub get` succeeds with path_provider added.
- `flutter analyze` reports zero errors in `lib/features/monitoring` and `lib/core` (warnings/info OK).
- New files exist: session.dart, session_history_repository.dart, session_history_provider.dart.
- `HealthEvent.toJson/fromJson` round-trips: a quick `dart` REPL sanity check would show `HealthEvent.fromJson(e.toJson()).type == e.type`.
- `startMonitoring` has an early-return guard referencing `sessionHistoryProvider` BEFORE the clear() call (grep `grep -n "startMonitoring called while session already in progress" lib/features/monitoring/providers/audio_player_provider.dart` returns 1 match).
  </done>
</task>

<task type="auto">
  <name>Task 2: ShellRoute + IndexedStack + NavigationBar + Stop FAB; refactor HealthSummaryScreen to take Session; remove the app-bar health-summary icon</name>
  <files>
    lib/core/widgets/main_shell.dart,
    lib/core/router/app_router.dart,
    lib/features/monitoring/screens/monitoring_screen.dart,
    lib/features/monitoring/widgets/stop_monitoring_button.dart,
    lib/features/monitoring/screens/health_summary_screen.dart,
    lib/features/monitoring/screens/sessions_list_screen.dart
  </files>
  <action>
1. lib/core/widgets/main_shell.dart: NEW. `class MainShell extends ConsumerStatefulWidget { final Widget child; final String currentLocation; }` — but since IndexedStack needs to keep all three tabs mounted across tab switches, do NOT use the ShellRoute's `child` parameter (which only renders the active route). Instead implement MainShell as a StatefulWidget that ignores `child` and renders an IndexedStack of `[MonitoringScreen(), SessionsListScreen(), LogScreen()]`. Determine selected index from `currentLocation`:
   - `/monitoring` → 0, `/sessions` (and `/sessions/:id` — but detail uses MaterialPageRoute via context.push, see step 4) → 1, `/logs` → 2.
   Body: `Column(children: [Expanded(child: IndexedStack(index: selectedIndex, children: [...])), ActiveSessionBar(selectedIndex: selectedIndex)])` — but ActiveSessionBar is the next task; for this task render a `const SizedBox.shrink()` placeholder where it will go. NavigationBar (M3): three NavigationDestination items (Monitor / Sessions / Logs) with icons `monitor_heart_outlined`, `history`, `article_outlined`. onDestinationSelected: `context.go(['/monitoring','/sessions','/logs'][i])`.
   Rationale comment in file: "IndexedStack keeps MonitoringScreen mounted across tab switches so the audio pipeline, video controllers, and ConsumerStatefulWidget state are not torn down on every navigation."

2. lib/core/router/app_router.dart: replace the three flat `GoRoute` entries for `/monitoring`, `/logs` with a single `ShellRoute(builder: (ctx, state, _child) => MainShell(currentLocation: state.matchedLocation), routes: [GoRoute(path:'/monitoring',...), GoRoute(path:'/sessions',...), GoRoute(path:'/sessions/:id',...), GoRoute(path:'/logs',...)])`. The ShellRoute's builder DOES NOT pass `_child` to MainShell (per rationale above — IndexedStack owns its own tab widgets). The sub-route builders can return `const SizedBox.shrink()` since the IndexedStack is what actually renders. EXCEPTION: `/sessions/:id` must build a real `HealthSummaryScreen(session: ...)` because it is NOT in the IndexedStack — it pushes on top of the shell. To make this work, switch `/sessions/:id` to use `pageBuilder` with `MaterialPage` so it stacks above the shell scaffold (this is the normal go_router pattern for detail-on-top-of-shell). Look up the session by id from `ref.read(sessionHistoryProvider).value` (check both `current` and `past`); if not found, show a simple "Session not found" Scaffold rather than crashing.
   Keep `/login` and `/cameras` OUTSIDE the ShellRoute. Auth redirect logic stays unchanged.

3. lib/features/monitoring/screens/monitoring_screen.dart:
   - Remove the entire `IconButton(icon: Icons.monitor_heart_outlined, ...)` from the AppBar `actions:` (lines ~155–164). The Sessions tab replaces it.
   - Remove the unused `import 'health_summary_screen.dart';` line.
   - Remove `bottomNavigationBar: const StopMonitoringButton(),` (line ~235).
   - Add `floatingActionButton:` showing a `FloatingActionButton.extended` only when `monitoringState.value?.cameras.isNotEmpty == true` AND `sessionHistoryProvider.value?.current != null`. Use `Theme.of(context).colorScheme.errorContainer` as `backgroundColor`, `onErrorContainer` as `foregroundColor`, `Icons.stop_rounded` as icon, label `'Stop monitoring'`. onPressed: the existing logic from `StopMonitoringButton` (delete `was_monitoring`, call `stopMonitoring`, stop foreground service, `context.go('/cameras')`).

4. lib/features/monitoring/widgets/stop_monitoring_button.dart: keep file but mark deprecated with `@Deprecated('Replaced by inline FAB on MonitoringScreen — see task 260514-siv plan')`. Do NOT delete in this task to keep diff isolated; will be removed in a follow-up cleanup. Add a TODO comment at the top.

5. lib/features/monitoring/screens/health_summary_screen.dart: change signature from `class HealthSummaryScreen extends ConsumerWidget { const HealthSummaryScreen({super.key}); }` to `class HealthSummaryScreen extends ConsumerWidget { final Session session; const HealthSummaryScreen({super.key, required this.session}); }`. Inside `build`:
   - Replace `final events = ref.watch(healthEventsProvider);` with `final events = session.events;`.
   - Replace `final monState = ref.watch(audioPlayerProvider).value; final cameras = monState?.cameras ?? const <CameraAudioState>[];` with: derive a lightweight `cameras` view from `session.cameras` (records). Update `_CamerasRow` / `_CameraTile` to take `({String id, String name})` instead of `CameraAudioState` — the existing fields used are only `cameraName` and `cameraId`. The `reconnectCountByCamera` and `_computeDowntimeByCamera` logic remains the same since it works off events.
   - Remove the unused `monitoringState` and `audio_player_provider.dart` import.
   - Title can show the session date: `AppBar(title: Text(_formatRange(session)))`.

6. lib/features/monitoring/screens/sessions_list_screen.dart: NEW. `class SessionsListScreen extends ConsumerWidget`. Watch `sessionHistoryProvider`. AppBar title 'Sessions'. Body:
   - `AsyncValue.when` standard handling.
   - On data: build a list with `current` first (if non-null) annotated "In progress" badge and a live ticker using `StreamBuilder` on `Stream.periodic(1s)` to show uptime; followed by `past` (most-recent first, repository already sorts that way). Empty state: centered Icon + 'No sessions yet'.
   - Each row: a Card with the date range, duration, total reconnects (count of events of type reconnectAttempt), total downtime computed via the same algorithm as `_computeDowntimeByCamera` summed across cameras.
   - Tap → `context.push('/sessions/${session.id}')`.
   Use existing `Spacing` constants from `lib/core/theme/spacing.dart`.
  </action>
  <verify>
    <automated>cd /Users/fvoska/projects/personal/rtsp-audio-mixer && flutter analyze lib 2>&1 | tee /tmp/analyze2.log && grep -E "error •" /tmp/analyze2.log | wc -l | awk '{exit ($1 > 0)}' && grep -c "monitor_heart_outlined" lib/features/monitoring/screens/monitoring_screen.dart | awk '{exit ($1 != 0)}'</automated>
  </verify>
  <done>
- `flutter analyze lib` reports zero errors (the deprecated StopMonitoringButton may produce one deprecation warning where it is still referenced — acceptable until follow-up cleanup; ensure it is a warning, not an error).
- `monitor_heart_outlined` no longer appears in `monitoring_screen.dart`.
- ShellRoute exists in app_router.dart (`grep -c "ShellRoute" lib/core/router/app_router.dart` returns 1).
- HealthSummaryScreen constructor takes `required Session session` (`grep -n "required this.session" lib/features/monitoring/screens/health_summary_screen.dart` matches).
- SessionsListScreen file exists with class `SessionsListScreen extends ConsumerWidget`.
- MainShell uses IndexedStack (`grep -n "IndexedStack" lib/core/widgets/main_shell.dart` matches once).
  </done>
</task>

<task type="auto">
  <name>Task 3: ActiveSessionBar mini-player widget, wired into MainShell</name>
  <files>
    lib/features/monitoring/widgets/active_session_bar.dart,
    lib/core/widgets/main_shell.dart
  </files>
  <action>
1. lib/features/monitoring/widgets/active_session_bar.dart: NEW. `class ActiveSessionBar extends ConsumerStatefulWidget { final int selectedIndex; const ActiveSessionBar({super.key, required this.selectedIndex}); }`. State holds a `Timer.periodic(Duration(seconds: 1))` to refresh uptime; cancel in `dispose`.
   - In `build`, watch `sessionHistoryProvider`. Visibility rule: render `const SizedBox.shrink()` if any of:
     a. `sessionHistoryProvider.value?.current == null`
     b. `widget.selectedIndex == 0` (already on Monitor tab)
   - Otherwise render a Material 3 surface: 48px tall, full width, `theme.colorScheme.secondaryContainer` background, rounded top corners. Row children:
     - Left: 8x8 green circular dot (use `AppTheme.statusOnline` color) inside an AnimatedOpacity that pulses between 0.5 and 1.0 every 1s for the "live" indicator.
     - Text: `'Monitoring · ${_formatUptime(now - session.startedAt)}'`. Style `theme.textTheme.titleSmall`.
     - Trailing chevron `Icons.expand_less` (visual hint to expand/return).
   - Wrap in `InkWell(onTap: () => context.go('/monitoring'))` so the whole bar is tappable. Add `Semantics(label: 'Return to monitoring, uptime ${...}', button: true)`.
   - Helper `String _formatUptime(Duration d)` identical to the one already in HealthSummaryScreen (xs/m/h m format).

2. lib/core/widgets/main_shell.dart: replace the `const SizedBox.shrink()` placeholder added in Task 2 with `ActiveSessionBar(selectedIndex: selectedIndex)`. Place it BETWEEN the IndexedStack (Expanded) and the NavigationBar in the Column — the layout becomes: `Column([Expanded(IndexedStack(...)), ActiveSessionBar(...), const SizedBox.shrink()])`. The NavigationBar stays in `bottomNavigationBar:` on the Scaffold (so SafeArea + system bottom padding behaves correctly). Therefore the ActiveSessionBar sits inside the body Column, ABOVE the Scaffold's bottomNavigationBar — exactly as specified in the description ("a slot for an ActiveSessionBar widget above the bottom NavigationBar"). Add a tiny rationale comment.
  </action>
  <verify>
    <automated>cd /Users/fvoska/projects/personal/rtsp-audio-mixer && flutter analyze lib/features/monitoring/widgets/active_session_bar.dart lib/core/widgets/main_shell.dart 2>&1 | tee /tmp/analyze3.log && grep -E "error •" /tmp/analyze3.log | wc -l | awk '{exit ($1 > 0)}' && grep -c "ActiveSessionBar" lib/core/widgets/main_shell.dart | awk '{exit ($1 < 2)}'</automated>
  </verify>
  <done>
- `active_session_bar.dart` exists and analyzes clean.
- `MainShell` imports and uses `ActiveSessionBar` (grep returns >= 2 hits — import + usage).
- Manual smoke (next step after plan execution, NOT required for `done`): launch app, start monitoring with two cameras, switch to Sessions tab — the bar appears at the bottom above the NavigationBar showing uptime and a pulsing green dot; tapping it returns to Monitor; switching back to Monitor hides the bar.
  </done>
</task>

</tasks>

<verification>
End-to-end smoke (manual, post-execution — not blocking on `done`):
1. Fresh install: open app, log in, select 2 cameras, start monitoring → Sessions tab shows 1 "In progress" session with live uptime.
2. Switch to Logs and back to Monitor → audio never stops, video preview state preserved, no reconnect storm in logs.
3. Switch to Sessions tab while monitoring → ActiveSessionBar appears above NavigationBar; tap returns to Monitor.
4. Tap Stop FAB → routed to `/cameras`; reopen the app, navigate to Sessions → the just-ended session is in `past`, tappable, opens HealthSummaryScreen with events.
5. Kill the app (swipe from recents) mid-session → reopen → Sessions still shows the session (debounced write may have been pre-empted by lifecycle paused flush).
6. Corrupt `sessions.json` on device (`adb shell` echo garbage) → open app → no crash; Sessions tab shows empty.

Automated gates (per task `verify`): zero `flutter analyze` errors across `lib/`, no removed-symbol references (grep gates above).
</verification>

<success_criteria>
- All three tasks' `done` criteria met.
- `lib/features/monitoring/services/session_history_repository.dart` writes to `<appDocumentsDir>/sessions.json` via atomic tmp+rename.
- `sessionHistoryProvider` flushes on `AppLifecycleState.paused` and `detached`.
- `audio_player_provider.startMonitoring` is idempotent (no clear, no restart, when a session is already in flight and players are connecting/connected).
- ShellRoute keeps `/monitoring`, `/sessions`, `/logs` mounted via IndexedStack; `/sessions/:id` stacks above as a MaterialPage.
- Stop button is gone from MonitoringScreen's bottomNavigationBar and is now an extended FAB shown only while a session is running.
- `HealthSummaryScreen` is parameterized by `Session` and no longer reads `healthEventsProvider`.
- `monitor_heart_outlined` icon button removed from MonitoringScreen AppBar.
- `flutter analyze lib` shows zero errors.
- No exception path in the new SESSION-tagged code can propagate to the audio pipeline (manual review: every disk/JSON op wrapped in try/catch with appLog).
</success_criteria>

<output>
After completion, create `.planning/quick/260514-siv-session-history/260514-siv-SUMMARY.md` documenting:
- Final file list with line-counts (sanity check on size).
- Decisions taken at the two planner-discretion points:
  (a) repository location (`lib/features/monitoring/services/` chosen over a new `lib/features/sessions/` folder — single feature, no need to split yet)
  (b) event forwarding strategy: `healthEventsProvider.record` forwards to `sessionHistoryProvider` rather than deriving healthEventsProvider from sessionHistory — lower blast radius.
- Any deviations from the plan and rationale.
- Known follow-ups: delete `stop_monitoring_button.dart` once no usages remain; add a unit test for `SessionHistoryRepository` corrupt-file path; consider migrating health_events_provider into a `select` over sessionHistoryProvider in a future cleanup.
</output>
