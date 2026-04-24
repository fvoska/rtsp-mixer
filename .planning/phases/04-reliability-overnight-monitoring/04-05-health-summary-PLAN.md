---
phase: 04-reliability-overnight-monitoring
plan: 05
type: execute
wave: 2
depends_on: [04-01-reconnect-core-PLAN.md]
files_modified:
  - lib/features/monitoring/screens/health_summary_screen.dart
  - lib/features/monitoring/screens/monitoring_screen.dart
  - test/features/monitoring/screens/health_summary_screen_test.dart
autonomous: true
requirements: [MNTR-01]
tags: [ui, flutter, material3, baby-monitor, health-summary, mntr-01]

must_haves:
  truths:
    - "MonitoringScreen AppBar has a new IconButton (Icons.monitor_heart_outlined) — tooltip 'Open health summary' — BEFORE the existing video-toggle icon"
    - "Tapping the icon opens HealthSummaryScreen via Navigator.push + MaterialPageRoute"
    - "HealthSummaryScreen renders session uptime (titleLarge), Cameras section (per-camera Reconnects + Downtime tiles), and Events section (chronological list)"
    - "Events list is reversed (newest on TOP) via `events.reversed.toList()` — NOT `ListView.builder(reverse: true)`"
    - "Per-camera reconnect count is derived from `events.where(type == reconnectAttempt).groupBy(cameraId)`"
    - "Session uptime is `DateTime.now().difference(monitoringStarted.timestamp)` when a monitoringStarted event exists; 0 otherwise"
    - "Empty state (only monitoringStarted event or fewer) renders 'Monitoring just started' heading + body text with `Icons.health_and_safety_outlined`"
    - "Stopped-session banner appears ABOVE the event list when the most recent event is `monitoringStopped`"
    - "All colors resolve via theme.colorScheme.* or AppTheme.status* — zero new Color constants"
    - "All spacing uses Spacing.* tokens — no raw EdgeInsets.all(N) with non-token values"
    - "No 'Clear events' button, no filter input, no copy-to-clipboard, no per-event tap detail (UI-SPEC §Out of Scope)"
    - "The summary icon has NO badge/dot (UI-SPEC §Registry Safety — no state subscription on the icon)"
  artifacts:
    - path: "lib/features/monitoring/screens/health_summary_screen.dart"
      provides: "HealthSummaryScreen ConsumerWidget rendering uptime header + per-camera tiles + event log + empty/stopped states"
      contains: "class HealthSummaryScreen"
    - path: "lib/features/monitoring/screens/monitoring_screen.dart"
      provides: "AppBar IconButton opening HealthSummaryScreen"
      contains: "HealthSummaryScreen"
    - path: "test/features/monitoring/screens/health_summary_screen_test.dart"
      provides: "Widget tests: renders uptime + per-camera counts, empty state, stopped banner, event row copy"
      contains: "HealthSummaryScreen"
  key_links:
    - from: "lib/features/monitoring/screens/health_summary_screen.dart"
      to: "lib/features/monitoring/providers/health_events_provider.dart"
      via: "ref.watch(healthEventsProvider) returns List<HealthEvent>"
      pattern: "ref\\.watch\\(healthEventsProvider\\)"
    - from: "lib/features/monitoring/screens/monitoring_screen.dart"
      to: "lib/features/monitoring/screens/health_summary_screen.dart"
      via: "IconButton onPressed Navigator.push MaterialPageRoute"
      pattern: "HealthSummaryScreen"
---

<objective>
Deliver MNTR-01 — the overnight health summary. Add a new screen that renders session uptime, per-camera reconnect counts + downtime, and a chronological event log with severity-colored icons per UI-SPEC. Add the entry point on MonitoringScreen's AppBar per UI-SPEC Component #2.

Purpose: MNTR-01 — the parent can review the overnight timeline and confirm the app kept monitoring (or see exactly what went wrong and when). Also serves as the recovery path for T-04-21 (alert-fired repudiation): the health summary independently records every alertFired regardless of whether the notification was delivered.
Output: One new screen + one AppBar IconButton + one widget test. Parallel-safe with Plans 04-02 (zombie) and 04-03 (card UI) — no shared files.
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

<interfaces>
<!-- Stable contracts. Plan 04-01 delivered the HealthEvent data path. -->

From lib/features/monitoring/models/health_event.dart (post-04-01):
```dart
enum HealthEventType {
  monitoringStarted, monitoringStopped,
  streamStarted, streamError,
  reconnectAttempt, reconnectSuccess,
  zombieDetected,
  wifiDropped, wifiReconnected,
  alertFired,
}

class HealthEvent {
  final DateTime timestamp;
  final HealthEventType type;
  final String? cameraId;
  final String? cameraName;
  final String? detail;
  const HealthEvent({...});
}
```

From lib/features/monitoring/providers/health_events_provider.dart (post-04-01):
```dart
class HealthEventsNotifier extends Notifier<List<HealthEvent>> {
  void record(HealthEvent event);
  void clear();
}
final healthEventsProvider = NotifierProvider<HealthEventsNotifier, List<HealthEvent>>(HealthEventsNotifier.new);
```

From lib/features/monitoring/providers/audio_player_provider.dart:
```dart
final audioPlayerProvider = /* AsyncNotifierProvider<MonitoringState> */;
// ref.watch(audioPlayerProvider).value returns MonitoringState? with .cameras : List<CameraAudioState>
```

From lib/features/monitoring/models/player_state.dart:
```dart
class CameraAudioState {
  final String cameraId;
  final String cameraName;
  final CameraConnectionStatus connectionStatus;
  // ...
}
```

From lib/core/theme/app_theme.dart:
- `AppTheme.statusOnline` — green
- `AppTheme.statusOffline` — red
- Theme accessed via `Theme.of(context)`

From lib/core/theme/spacing.dart: `Spacing.xs=4, sm=8, md=16, lg=24, xl=32, xxl=48`.

UI-SPEC authoritative layout + copy (see §Component Inventory #3 + §Copywriting Contract > Event log row copy contract):

Layout (top→bottom): AppBar(title: 'Health summary') → Session uptime Card.filled (label bodySmall onSurfaceVariant + value titleLarge onSurface) → 'Cameras' titleMedium → Row of per-camera Card.filled tiles (name titleMedium, 'Reconnects' / count, 'Downtime' / value) → 'Events' titleMedium → stopped-session banner (conditional) → Expanded ListView.builder with reversed data → _EventRow per event.

Severity → color mapping (for event icons):
- positive (`statusOnline`): monitoringStarted, streamStarted, reconnectSuccess
- destructive (`statusOffline`): streamError, zombieDetected
- warning (`colorScheme.tertiary`): reconnectAttempt, wifiDropped, alertFired
- info (`colorScheme.primary`): wifiReconnected
- neutral (`colorScheme.onSurfaceVariant`): monitoringStopped

Icons (Material Icons — bundled via uses-material-design: true):
- monitoringStarted: `Icons.play_circle_outline`
- monitoringStopped: `Icons.stop_circle_outlined`
- streamStarted: `Icons.play_arrow`
- streamError: `Icons.error_outline`
- reconnectAttempt: `Icons.refresh`
- reconnectSuccess: `Icons.check_circle_outline`
- zombieDetected: `Icons.warning_amber_outlined`
- wifiDropped: `Icons.wifi_off`
- wifiReconnected: `Icons.wifi`
- alertFired: `Icons.notifications_active_outlined`

Row format: `[icon] HH:mm:ss · {cameraName or 'Session'} · {label}` + optional second line `{detail}` bodySmall onSurfaceVariant indented Spacing.lg.

Monitoring screen AppBar add (UI-SPEC Component #2):
- Icon: `Icons.monitor_heart_outlined`
- Tooltip: `Open health summary`
- Inserted BEFORE the existing video-toggle IconButton
- Default tint (colorScheme.onSurface — NOT accent)

Accessibility + type-safety requirements (UI-SPEC §Accessibility Contract + PATTERNS.md):
- Every event-row leading icon MUST be wrapped in `Semantics(label: labelForType(event.type), child: Icon(...))` — screen readers announce the event type since the icon is purely visual.
- `_CamerasRow.cameras` MUST be typed `List<CameraAudioState>` (import `../models/player_state.dart`) — NO `List<dynamic>` and NO runtime `as String` casts on `cameraId` / `cameraName`.
</interfaces>
</context>

<tasks>

<task type="auto" tdd="true">
  <name>Task 1: Build HealthSummaryScreen with session uptime, per-camera counters, event list, empty + stopped states</name>
  <files>
    lib/features/monitoring/screens/health_summary_screen.dart,
    test/features/monitoring/screens/health_summary_screen_test.dart
  </files>
  <read_first>
    - .planning/phases/04-reliability-overnight-monitoring/04-UI-SPEC.md §Component Inventory #3 (HealthSummaryScreen contract), §Copywriting Contract (exact copy strings), §Color (severity map), §Typography (bodyMedium/bodySmall/titleMedium/titleLarge usage), §Spacing Scale, §Out of Scope, §Interaction States Matrix
    - .planning/phases/04-reliability-overnight-monitoring/04-PATTERNS.md §11 (HealthSummaryScreen — LogScreen analog, Scaffold shell, ConsumerWidget, reversed data rule, severity → color mapping anti-pattern warnings), §Shared Patterns
    - .planning/phases/04-reliability-overnight-monitoring/04-RESEARCH.md §Section 6 (event stream shape, derived per-camera counts via groupBy)
    - .planning/phases/04-reliability-overnight-monitoring/04-CONTEXT.md §decisions D-13 (session-scoped), D-15 (all 10 event types), D-16 (app bar access, summary layout discretion), D-17 (1000-event cap)
    - .planning/phases/04-reliability-overnight-monitoring/04-VALIDATION.md §Per-Task Verification Map (widget test row)
    - lib/features/monitoring/screens/log_screen.dart (ENTIRE FILE — closest analog for Scaffold/AppBar/ListView pattern; copy structural layout, NOT the monospace/filter/copy-to-clipboard bits that are out of scope)
    - lib/core/theme/app_theme.dart
    - lib/core/theme/spacing.dart
    - lib/features/monitoring/providers/health_events_provider.dart (from 04-01)
    - lib/features/monitoring/models/health_event.dart (from 04-01)
    - lib/features/monitoring/models/player_state.dart
  </read_first>
  <behavior>
    - Widget test 1: pumping with an empty events list (list == `const []`) renders the empty state — finds `'Monitoring just started'` text and `Icons.health_and_safety_outlined`.
    - Widget test 2: pumping with events `[monitoringStarted, streamStarted(cam1), reconnectAttempt(cam1), reconnectSuccess(cam1)]` renders non-empty — reconnectCount for cam1 == 1, shows a 'Cameras' section header, and at least 3 event rows.
    - Widget test 3: pumping with events whose LAST entry is `monitoringStopped` shows the stopped-session banner text `'Monitoring stopped. Start monitoring to reset the session.'`.
    - Widget test 4: with an event whose cameraName is null, the event row uses `'Session'` as the middle segment (tests the fallback).
    - Widget test 5: events list is rendered newest-on-top: given two events at t=1000 and t=2000 ms, the widget tree has the t=2000 event's ListTile ABOVE the t=1000 event's ListTile. Simplest assertion: find both by their detail text and assert `tester.getTopLeft(newer).dy < tester.getTopLeft(older).dy`.
    - Widget test 6: the AppBar shows exactly `'Health summary'` (the literal title).
    - Widget test 7: NO Text widget contains `'attempt 3'`-style derived copy for data that isn't in the `detail` field — i.e., we DON'T invent copy; detail strings are rendered verbatim. (Regression guard for UI-SPEC row format rules.)
  </behavior>
  <action>
    Step A — Create lib/features/monitoring/screens/health_summary_screen.dart:

    ```dart
    import 'package:flutter/material.dart';
    import 'package:flutter_riverpod/flutter_riverpod.dart';

    import '../../../core/theme/app_theme.dart';
    import '../../../core/theme/spacing.dart';
    import '../models/health_event.dart';
    import '../models/player_state.dart';
    import '../providers/audio_player_provider.dart';
    import '../providers/health_events_provider.dart';

    /// MNTR-01: session-scoped overnight health summary.
    /// Reads healthEventsProvider + audioPlayerProvider (for camera names).
    /// Session boundaries: events list is cleared on startMonitoring (D-13).
    class HealthSummaryScreen extends ConsumerWidget {
      const HealthSummaryScreen({super.key});

      @override
      Widget build(BuildContext context, WidgetRef ref) {
        final theme = Theme.of(context);
        final events = ref.watch(healthEventsProvider);
        final monState = ref.watch(audioPlayerProvider).value;
        final cameras = monState?.cameras ?? const [];

        final startedEvent = events
            .where((e) => e.type == HealthEventType.monitoringStarted)
            .fold<HealthEvent?>(null, (_, e) => e);
        final isStoppedSession = events.isNotEmpty &&
            events.last.type == HealthEventType.monitoringStopped;

        // Non-trivial events = everything except the implicit monitoringStarted row.
        final nonTrivial = events.where(
          (e) => e.type != HealthEventType.monitoringStarted,
        );
        final isEmpty = nonTrivial.isEmpty;

        final reconnectCountByCamera = <String, int>{};
        for (final e in events) {
          if (e.type == HealthEventType.reconnectAttempt && e.cameraId != null) {
            reconnectCountByCamera[e.cameraId!] =
                (reconnectCountByCamera[e.cameraId!] ?? 0) + 1;
          }
        }

        final downtimeByCamera = _computeDowntimeByCamera(events);

        return Scaffold(
          appBar: AppBar(
            title: const Text('Health summary'),
          ),
          body: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.lg,
              vertical: Spacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SessionUptimeCard(startedAt: startedEvent?.timestamp),
                const SizedBox(height: Spacing.lg),
                if (cameras.isNotEmpty) ...[
                  Text('Cameras', style: theme.textTheme.titleMedium),
                  const SizedBox(height: Spacing.sm),
                  _CamerasRow(
                    cameras: cameras,
                    reconnectCount: reconnectCountByCamera,
                    downtime: downtimeByCamera,
                  ),
                  const SizedBox(height: Spacing.lg),
                ],
                Text('Events', style: theme.textTheme.titleMedium),
                const SizedBox(height: Spacing.sm),
                if (isStoppedSession) ...[
                  _StoppedSessionBanner(),
                  const SizedBox(height: Spacing.sm),
                ],
                if (isEmpty)
                  const Expanded(child: _EmptyEvents())
                else
                  Expanded(
                    child: Builder(
                      builder: (_) {
                        final reversed = events.reversed.toList();
                        return ListView.builder(
                          itemCount: reversed.length,
                          itemBuilder: (_, i) => _EventRow(event: reversed[i]),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      }

      /// Computes per-camera downtime by summing (reconnectSuccess - streamError) windows.
      /// A window opens on streamError / zombieDetected; closes on the next reconnectSuccess
      /// or streamStarted for the same cameraId.
      Map<String, Duration> _computeDowntimeByCamera(List<HealthEvent> events) {
        final openFrom = <String, DateTime>{};
        final total = <String, Duration>{};
        for (final e in events) {
          final id = e.cameraId;
          if (id == null) continue;
          final opens = e.type == HealthEventType.streamError ||
              e.type == HealthEventType.zombieDetected;
          final closes = e.type == HealthEventType.reconnectSuccess ||
              e.type == HealthEventType.streamStarted;
          if (opens && openFrom[id] == null) {
            openFrom[id] = e.timestamp;
          } else if (closes && openFrom[id] != null) {
            final d = e.timestamp.difference(openFrom[id]!);
            total[id] = (total[id] ?? Duration.zero) + d;
            openFrom[id] = null;
          }
        }
        return total;
      }
    }

    class _SessionUptimeCard extends StatelessWidget {
      const _SessionUptimeCard({required this.startedAt});
      final DateTime? startedAt;

      @override
      Widget build(BuildContext context) {
        final theme = Theme.of(context);
        final uptime = startedAt != null
            ? DateTime.now().difference(startedAt!)
            : Duration.zero;
        return Card.filled(
          child: Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Session uptime',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: Spacing.xs),
                Text(
                  _formatUptime(uptime),
                  style: theme.textTheme.titleLarge,
                ),
              ],
            ),
          ),
        );
      }

      String _formatUptime(Duration d) {
        if (d.inMinutes < 1) return '${d.inSeconds}s';
        if (d.inHours < 1) return '${d.inMinutes}m';
        final h = d.inHours;
        final m = d.inMinutes - h * 60;
        return '${h}h ${m}m';
      }
    }

    class _CamerasRow extends StatelessWidget {
      const _CamerasRow({
        required this.cameras,
        required this.reconnectCount,
        required this.downtime,
      });
      final List<CameraAudioState> cameras;
      final Map<String, int> reconnectCount;
      final Map<String, Duration> downtime;

      @override
      Widget build(BuildContext context) {
        final children = <Widget>[];
        for (var i = 0; i < cameras.length; i++) {
          final cam = cameras[i];
          children.add(Expanded(
            child: _CameraTile(
              name: cam.cameraName,
              reconnects: reconnectCount[cam.cameraId] ?? 0,
              downtime: downtime[cam.cameraId] ?? Duration.zero,
            ),
          ));
          if (i < cameras.length - 1) {
            children.add(const SizedBox(width: Spacing.md));
          }
        }
        return Row(children: children);
      }
    }

    class _CameraTile extends StatelessWidget {
      const _CameraTile({
        required this.name,
        required this.reconnects,
        required this.downtime,
      });
      final String name;
      final int reconnects;
      final Duration downtime;

      @override
      Widget build(BuildContext context) {
        final theme = Theme.of(context);
        return Card.filled(
          child: Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: theme.textTheme.titleMedium),
                const SizedBox(height: Spacing.sm),
                _MetricRow(
                  label: 'Reconnects',
                  value: '$reconnects',
                ),
                const SizedBox(height: Spacing.xs),
                _MetricRow(
                  label: 'Downtime',
                  value: _formatDowntime(downtime),
                ),
              ],
            ),
          ),
        );
      }

      String _formatDowntime(Duration d) {
        if (d == Duration.zero) return '—';
        if (d.inMinutes < 1) return '${d.inSeconds}s';
        final m = d.inMinutes;
        final s = d.inSeconds - m * 60;
        return '${m}m ${s}s';
      }
    }

    class _MetricRow extends StatelessWidget {
      const _MetricRow({required this.label, required this.value});
      final String label;
      final String value;

      @override
      Widget build(BuildContext context) {
        final theme = Theme.of(context);
        return Row(
          children: [
            Text(
              label,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const Spacer(),
            Text(value, style: theme.textTheme.titleMedium),
          ],
        );
      }
    }

    class _StoppedSessionBanner extends StatelessWidget {
      @override
      Widget build(BuildContext context) {
        final theme = Theme.of(context);
        return Container(
          padding: const EdgeInsets.all(Spacing.sm),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            'Monitoring stopped. Start monitoring to reset the session.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        );
      }
    }

    class _EmptyEvents extends StatelessWidget {
      const _EmptyEvents();

      @override
      Widget build(BuildContext context) {
        final theme = Theme.of(context);
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.health_and_safety_outlined,
                size: 48,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: Spacing.md),
              Text(
                'Monitoring just started',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: Spacing.sm),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
                child: Text(
                  'Events will appear here as the session runs — reconnects, WiFi changes, and alerts.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        );
      }
    }

    class _EventRow extends StatelessWidget {
      const _EventRow({required this.event});
      final HealthEvent event;

      @override
      Widget build(BuildContext context) {
        final theme = Theme.of(context);
        final iconData = _iconForType(event.type);
        final color = _colorForType(event.type, theme);
        final label = _labelForType(event.type);
        final timestamp = _formatHms(event.timestamp);
        final camera = event.cameraName ?? 'Session';
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 24,
                    // UI-SPEC §Accessibility Contract: wrap icon in Semantics(label: labelForType)
                    // so screen readers announce the event type (icon is purely visual).
                    child: Semantics(
                      label: label,
                      child: Icon(iconData, size: 20, color: color),
                    ),
                  ),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: Text(
                      '$timestamp · $camera · $label',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurface),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              if (event.detail != null && event.detail!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(
                    left: Spacing.lg,
                    top: Spacing.xs,
                  ),
                  child: Text(
                    event.detail!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        );
      }

      String _formatHms(DateTime ts) {
        String two(int n) => n.toString().padLeft(2, '0');
        return '${two(ts.hour)}:${two(ts.minute)}:${two(ts.second)}';
      }

      IconData _iconForType(HealthEventType t) {
        switch (t) {
          case HealthEventType.monitoringStarted:
            return Icons.play_circle_outline;
          case HealthEventType.monitoringStopped:
            return Icons.stop_circle_outlined;
          case HealthEventType.streamStarted:
            return Icons.play_arrow;
          case HealthEventType.streamError:
            return Icons.error_outline;
          case HealthEventType.reconnectAttempt:
            return Icons.refresh;
          case HealthEventType.reconnectSuccess:
            return Icons.check_circle_outline;
          case HealthEventType.zombieDetected:
            return Icons.warning_amber_outlined;
          case HealthEventType.wifiDropped:
            return Icons.wifi_off;
          case HealthEventType.wifiReconnected:
            return Icons.wifi;
          case HealthEventType.alertFired:
            return Icons.notifications_active_outlined;
        }
      }

      Color _colorForType(HealthEventType t, ThemeData theme) {
        switch (t) {
          case HealthEventType.monitoringStarted:
          case HealthEventType.streamStarted:
          case HealthEventType.reconnectSuccess:
            return AppTheme.statusOnline;
          case HealthEventType.streamError:
          case HealthEventType.zombieDetected:
            return AppTheme.statusOffline;
          case HealthEventType.reconnectAttempt:
          case HealthEventType.wifiDropped:
          case HealthEventType.alertFired:
            return theme.colorScheme.tertiary;
          case HealthEventType.wifiReconnected:
            return theme.colorScheme.primary;
          case HealthEventType.monitoringStopped:
            return theme.colorScheme.onSurfaceVariant;
        }
      }

      String _labelForType(HealthEventType t) {
        switch (t) {
          case HealthEventType.monitoringStarted:
            return 'Monitoring started';
          case HealthEventType.monitoringStopped:
            return 'Monitoring stopped';
          case HealthEventType.streamStarted:
            return 'Stream started';
          case HealthEventType.streamError:
            return 'Stream error';
          case HealthEventType.reconnectAttempt:
            return 'Reconnect attempt';
          case HealthEventType.reconnectSuccess:
            return 'Reconnected';
          case HealthEventType.zombieDetected:
            return 'Zombie stream detected';
          case HealthEventType.wifiDropped:
            return 'WiFi lost';
          case HealthEventType.wifiReconnected:
            return 'WiFi reconnected';
          case HealthEventType.alertFired:
            return '5-minute alert sent';
        }
      }
    }
    ```

    Step B — Create test/features/monitoring/screens/health_summary_screen_test.dart:

    ```dart
    import 'package:flutter/material.dart';
    import 'package:flutter_riverpod/flutter_riverpod.dart';
    import 'package:flutter_test/flutter_test.dart';
    import 'package:rtsp_mixer/core/theme/app_theme.dart';
    import 'package:rtsp_mixer/features/monitoring/models/health_event.dart';
    import 'package:rtsp_mixer/features/monitoring/providers/health_events_provider.dart';
    import 'package:rtsp_mixer/features/monitoring/screens/health_summary_screen.dart';

    HealthEvent _evt({
      required HealthEventType type,
      int tsMs = 0,
      String? cameraId,
      String? cameraName,
      String? detail,
    }) =>
        HealthEvent(
          timestamp: DateTime.fromMillisecondsSinceEpoch(tsMs),
          type: type,
          cameraId: cameraId,
          cameraName: cameraName,
          detail: detail,
        );

    Future<void> _pumpSummary(
      WidgetTester tester,
      List<HealthEvent> events,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            healthEventsProvider.overrideWith(() {
              final n = _PrefilledHealthEventsNotifier(events);
              return n;
            }),
          ],
          child: MaterialApp(
            theme: AppTheme.dark,
            home: const HealthSummaryScreen(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }

    class _PrefilledHealthEventsNotifier extends HealthEventsNotifier {
      _PrefilledHealthEventsNotifier(this._initial);
      final List<HealthEvent> _initial;
      @override
      List<HealthEvent> build() => List<HealthEvent>.from(_initial);
    }

    void main() {
      group('HealthSummaryScreen (MNTR-01)', () {
        testWidgets('AppBar shows "Health summary"', (tester) async {
          await _pumpSummary(tester, const []);
          expect(find.text('Health summary'), findsOneWidget);
        });

        testWidgets('empty state renders "Monitoring just started"', (tester) async {
          await _pumpSummary(tester, const []);
          expect(find.text('Monitoring just started'), findsOneWidget);
          expect(find.byIcon(Icons.health_and_safety_outlined), findsOneWidget);
        });

        testWidgets('renders "Session uptime" label', (tester) async {
          await _pumpSummary(tester, [
            _evt(type: HealthEventType.monitoringStarted, tsMs: 1000),
          ]);
          expect(find.text('Session uptime'), findsOneWidget);
        });

        testWidgets('events list renders newest-on-top', (tester) async {
          await _pumpSummary(tester, [
            _evt(
              type: HealthEventType.reconnectAttempt,
              tsMs: 1000,
              cameraId: 'cam1',
              cameraName: 'Nursery',
              detail: 'older-event',
            ),
            _evt(
              type: HealthEventType.reconnectAttempt,
              tsMs: 2000,
              cameraId: 'cam1',
              cameraName: 'Nursery',
              detail: 'newer-event',
            ),
          ]);
          final older = find.text('older-event');
          final newer = find.text('newer-event');
          expect(older, findsOneWidget);
          expect(newer, findsOneWidget);
          final olderY = tester.getTopLeft(older).dy;
          final newerY = tester.getTopLeft(newer).dy;
          expect(newerY, lessThan(olderY), reason: 'newer must render above older (reversed data)');
        });

        testWidgets('stopped-session banner appears when last event is monitoringStopped', (tester) async {
          await _pumpSummary(tester, [
            _evt(type: HealthEventType.monitoringStarted, tsMs: 1000),
            _evt(type: HealthEventType.monitoringStopped, tsMs: 2000),
          ]);
          expect(
            find.text('Monitoring stopped. Start monitoring to reset the session.'),
            findsOneWidget,
          );
        });

        testWidgets('event with null cameraName renders as "Session"', (tester) async {
          await _pumpSummary(tester, [
            _evt(type: HealthEventType.wifiDropped, tsMs: 1000),
          ]);
          // Row text is "HH:mm:ss · Session · WiFi lost"
          expect(find.textContaining('Session'), findsWidgets);
          expect(find.textContaining('WiFi lost'), findsOneWidget);
        });

        testWidgets('event row shows correct label copy for each event type', (tester) async {
          await _pumpSummary(tester, [
            _evt(type: HealthEventType.reconnectAttempt, tsMs: 1000, cameraName: 'Nursery'),
            _evt(type: HealthEventType.reconnectSuccess, tsMs: 2000, cameraName: 'Nursery'),
            _evt(type: HealthEventType.alertFired, tsMs: 3000, cameraName: 'Nursery'),
            _evt(type: HealthEventType.zombieDetected, tsMs: 4000, cameraName: 'Nursery', detail: 'PTS stall + buffering stuck'),
          ]);
          expect(find.textContaining('Reconnect attempt'), findsOneWidget);
          expect(find.textContaining('Reconnected'), findsOneWidget);
          expect(find.textContaining('5-minute alert sent'), findsOneWidget);
          expect(find.textContaining('Zombie stream detected'), findsOneWidget);
          // detail rendered on its own line
          expect(find.text('PTS stall + buffering stuck'), findsOneWidget);
        });
      });
    }
    ```

    Step C — Verify:
      Run `flutter analyze --no-preamble lib test` — zero issues.
      Run `flutter test test/features/monitoring/screens/health_summary_screen_test.dart` — all 7 tests green.
  </action>
  <verify>
    <automated>flutter analyze --no-preamble lib test &amp;&amp; flutter test --reporter expanded test/features/monitoring/screens/health_summary_screen_test.dart</automated>
  </verify>
  <acceptance_criteria>
    - `test -f lib/features/monitoring/screens/health_summary_screen.dart` exits 0
    - `grep "class HealthSummaryScreen extends ConsumerWidget" lib/features/monitoring/screens/health_summary_screen.dart` exits 0
    - `grep "'Health summary'" lib/features/monitoring/screens/health_summary_screen.dart` exits 0
    - `grep "'Monitoring just started'" lib/features/monitoring/screens/health_summary_screen.dart` exits 0
    - `grep "'Monitoring stopped. Start monitoring to reset the session.'" lib/features/monitoring/screens/health_summary_screen.dart` exits 0
    - `grep "events.reversed" lib/features/monitoring/screens/health_summary_screen.dart` exits 0
    - `grep "Icons.health_and_safety_outlined" lib/features/monitoring/screens/health_summary_screen.dart` exits 0
    - `grep "Icons.monitor_heart_outlined" lib/features/monitoring/screens/health_summary_screen.dart` exits 1 (that icon belongs to MonitoringScreen, not this screen)
    - `grep -E "Semantics\(\s*label: label," lib/features/monitoring/screens/health_summary_screen.dart` exits 0 (event icons wrapped per UI-SPEC §Accessibility Contract)
    - `grep "List<CameraAudioState> cameras" lib/features/monitoring/screens/health_summary_screen.dart` exits 0 (typed _CamerasRow — no List<dynamic>)
    - `grep "as String" lib/features/monitoring/screens/health_summary_screen.dart` exits 1 (no runtime String casts — type-safe access)
    - `grep -E "Icons\.(play_circle_outline|stop_circle_outlined|play_arrow|error_outline|refresh|check_circle_outline|warning_amber_outlined|wifi_off|wifi|notifications_active_outlined)" lib/features/monitoring/screens/health_summary_screen.dart` shows ≥ 10 matches (one per HealthEventType)
    - `grep "colorScheme.tertiary" lib/features/monitoring/screens/health_summary_screen.dart` exits 0
    - `grep "colorScheme.primary" lib/features/monitoring/screens/health_summary_screen.dart` exits 0
    - `grep "AppTheme.statusOnline\\|AppTheme.statusOffline" lib/features/monitoring/screens/health_summary_screen.dart` shows ≥ 2 lines
    - `grep "Colors\\." lib/features/monitoring/screens/health_summary_screen.dart` exits 1 (no hardcoded Colors.*)
    - `grep "EdgeInsets.all(" lib/features/monitoring/screens/health_summary_screen.dart | grep -v "Spacing\\."` returns nothing (every EdgeInsets.all uses a Spacing token)
    - `grep "TextField\\|filter\\|copyToClipboard\\|Clipboard\\.setData" lib/features/monitoring/screens/health_summary_screen.dart` exits 1 (UI-SPEC §Out of Scope — none of these)
    - `grep "'Clear events'" lib/features/monitoring/screens/health_summary_screen.dart` exits 1
    - `test -f test/features/monitoring/screens/health_summary_screen_test.dart` exits 0
    - `flutter test test/features/monitoring/screens/health_summary_screen_test.dart` reports 7 tests passed
    - `flutter analyze --no-preamble lib test` exits 0
  </acceptance_criteria>
  <done>
    HealthSummaryScreen fully renders per UI-SPEC §Component Inventory #3, with correct copy, severity-mapped icons, session-scoped derived counters, reversed-newest-first event list, empty/stopped states, and widget-test coverage for every key render path.
  </done>
</task>

<task type="auto" tdd="true">
  <name>Task 2: Add AppBar IconButton on MonitoringScreen opening HealthSummaryScreen</name>
  <files>
    lib/features/monitoring/screens/monitoring_screen.dart
  </files>
  <read_first>
    - .planning/phases/04-reliability-overnight-monitoring/04-UI-SPEC.md §Component Inventory #2 (MonitoringScreen AppBar addition — icon, tooltip, position, tint rules, NO badge)
    - .planning/phases/04-reliability-overnight-monitoring/04-PATTERNS.md §10 (monitoring_screen.dart AppBar modification)
    - .planning/phases/04-reliability-overnight-monitoring/04-CONTEXT.md §decisions D-16 (app bar icon + summary screen)
    - lib/features/monitoring/screens/monitoring_screen.dart (ENTIRE FILE — AppBar currently at lines 152–163 with the existing video-toggle IconButton)
    - lib/features/monitoring/screens/health_summary_screen.dart (created in Task 1)
  </read_first>
  <behavior>
    - MonitoringScreen's AppBar actions list now contains TWO IconButtons; the new summary button is FIRST (leftmost in actions), the existing video-toggle is SECOND.
    - New IconButton uses Icons.monitor_heart_outlined, tooltip 'Open health summary', default (no explicit color override), and onPressed calls Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HealthSummaryScreen())).
    - The icon does NOT subscribe to any provider (UI-SPEC §Registry Safety — no badge/dot in v1).
    - Existing video-toggle IconButton behavior is unchanged.
  </behavior>
  <action>
    Step A — Add import at top of monitoring_screen.dart (with other monitoring-screen imports):
    ```dart
    import 'health_summary_screen.dart';
    ```

    Step B — Locate the `AppBar` in `build(BuildContext context)` (current lines 152–163 in the `Scaffold(appBar: AppBar(...))` structure). The `actions:` list currently has exactly one entry (the video-toggle IconButton). Replace the `actions:` list with:

    ```dart
    actions: [
      IconButton(
        icon: const Icon(Icons.monitor_heart_outlined),
        tooltip: 'Open health summary',
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const HealthSummaryScreen(),
          ),
        ),
      ),
      IconButton(
        icon: Icon(_globalVideo ? Icons.videocam : Icons.videocam_off),
        tooltip: _globalVideo
            ? 'Hide all video previews'
            : 'Show all video previews',
        onPressed: _toggleGlobalVideo,
      ),
    ],
    ```

    Do NOT modify any other part of the file (initState, dispose, body, lifecycle observer, etc.).

    Step C — Verify:
      Run `flutter analyze --no-preamble lib test` — zero issues.
      Run `flutter test` — full suite green (widget test from Plan 04-03 against CameraAudioCard still passes; Plan 04-05 Task 1 HealthSummaryScreen test still passes).
  </action>
  <verify>
    <automated>flutter analyze --no-preamble lib test &amp;&amp; flutter test --reporter expanded</automated>
  </verify>
  <acceptance_criteria>
    - `grep "import 'health_summary_screen.dart'" lib/features/monitoring/screens/monitoring_screen.dart` exits 0
    - `grep "Icons.monitor_heart_outlined" lib/features/monitoring/screens/monitoring_screen.dart` exits 0
    - `grep "'Open health summary'" lib/features/monitoring/screens/monitoring_screen.dart` exits 0
    - `grep "MaterialPageRoute" lib/features/monitoring/screens/monitoring_screen.dart` exits 0
    - `grep "HealthSummaryScreen" lib/features/monitoring/screens/monitoring_screen.dart` exits 0
    - The order of IconButtons is summary-first, then video-toggle: `grep -n "Icons.monitor_heart_outlined\\|Icons.videocam" lib/features/monitoring/screens/monitoring_screen.dart` shows the monitor_heart line number STRICTLY LESS than the videocam line number
    - `flutter analyze --no-preamble lib test` exits 0
    - `flutter test` full suite passes
  </acceptance_criteria>
  <done>
    MonitoringScreen AppBar has a new summary icon in position-1 that opens HealthSummaryScreen via standard Navigator.push. Existing video-toggle unchanged. No badge, no state subscription.
  </done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| HealthSummaryScreen rendering ↔ HealthEventsNotifier state | Read-only consumer; the screen cannot write to the events list. |
| Event `detail` field ↔ Text widget rendering | Detail strings originate from error.toString() or supervisor-generated strings. |
| Navigator.push ↔ app route stack | Standard Flutter modal push — no deep-link surface. |

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-04-25 | Information Disclosure | `event.detail` text rendered on screen may contain verbose error messages with internal paths | accept | Detail strings are bounded to `maxLines: 2` + `TextOverflow.ellipsis`. Origin is media_kit's sanitized error.toString() (see T-04-04 in Plan 04-01). User is already logged-in; screen is on-device. No new attack surface. |
| T-04-26 | Denial of Service | Rendering 1000 events at once causes jank on low-end devices | mitigate | `ListView.builder` virtualizes rendering — only visible rows are built. `events.reversed.toList()` creates ONE reversed copy per rebuild (1000 items × pointer copy, negligible at 250 bytes × 1000). RESEARCH §Pitfall 7 suggests optional circular-buffer optimization; NOT adopted in v1 (the naive path is acceptable per memory budget). |
| T-04-27 | Tampering | User-visible event data could be misleading if record() is called out of chronological order | accept | All record() calls in AudioPlayerNotifier pass `DateTime.now()` — events are append-only in real time. No user input feeds into the event stream. |
| T-04-28 | Repudiation | User claims "event appeared without cause" | mitigate | Every event type has a specific trigger site in AudioPlayerNotifier (see Plans 04-01/02/04). The health summary correlates 1:1 with the appLog('HEALTH', ...) call that happens inside HealthEventsNotifier.record — two independent audit trails. |
| T-04-29 | Elevation of Privilege | Navigator.push to HealthSummaryScreen could be exploited if route is registered as a deep link | accept | Not registered in GoRouter (see Plan 04-01 use of Navigator.push + MaterialPageRoute — intentionally NOT a named route). No deep-link exposure. |
</threat_model>

<verification>
- `flutter test test/features/monitoring/screens/health_summary_screen_test.dart` passes with 7 tests
- `flutter test` full suite remains green (no regressions from any prior plan)
- Grep confirms: ConsumerWidget + `ref.watch(healthEventsProvider)`, reversed data rendering, all 10 event-type icons mapped, severity → theme-role color mapping, exact UI-SPEC copy strings present (empty state heading, stopped banner text, app bar title)
- Grep confirms NO out-of-scope widgets (TextField/filter/Clipboard)
- MonitoringScreen imports HealthSummaryScreen and its AppBar has the two icons in the correct order (summary first)
</verification>

<success_criteria>
- MNTR-01 complete: overnight health summary accessible via AppBar icon; renders session uptime, per-camera reconnect count + downtime, chronological newest-on-top event log.
- UI-SPEC Copywriting Contract enforced verbatim (title, empty state heading/body, stopped banner, event labels).
- UI-SPEC §Out of Scope enforced (no filter, no copy button, no clear-events, no tap detail, no badge).
- No regressions — all prior tests remain green.
</success_criteria>

<output>
After completion, create `.planning/phases/04-reliability-overnight-monitoring/04-05-SUMMARY.md` noting: derived metric computation (reconnect-count groupBy + downtime open/close windows), the reversed-data-not-reversed-list rendering choice, the ConsumerWidget vs ConsumerStatefulWidget decision, and the override strategy used in widget tests (_PrefilledHealthEventsNotifier subclassing HealthEventsNotifier + providerOverrideWith).
</output>
