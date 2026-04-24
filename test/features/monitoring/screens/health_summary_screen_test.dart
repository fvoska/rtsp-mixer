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
        healthEventsProvider.overrideWith(
          () => _PrefilledHealthEventsNotifier(events),
        ),
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
      expect(newerY, lessThan(olderY),
          reason: 'newer must render above older (reversed data)');
    });

    testWidgets(
        'stopped-session banner appears when last event is monitoringStopped',
        (tester) async {
      await _pumpSummary(tester, [
        _evt(type: HealthEventType.monitoringStarted, tsMs: 1000),
        _evt(type: HealthEventType.monitoringStopped, tsMs: 2000),
      ]);
      expect(
        find.text('Monitoring stopped. Start monitoring to reset the session.'),
        findsOneWidget,
      );
    });

    testWidgets('event with null cameraName renders as "Session"',
        (tester) async {
      await _pumpSummary(tester, [
        _evt(type: HealthEventType.wifiDropped, tsMs: 1000),
      ]);
      // Row text is "HH:mm:ss · Session · WiFi lost"
      expect(find.textContaining('Session'), findsWidgets);
      expect(find.textContaining('WiFi lost'), findsOneWidget);
    });

    testWidgets('event row shows correct label copy for each event type',
        (tester) async {
      await _pumpSummary(tester, [
        _evt(
            type: HealthEventType.reconnectAttempt,
            tsMs: 1000,
            cameraName: 'Nursery'),
        _evt(
            type: HealthEventType.reconnectSuccess,
            tsMs: 2000,
            cameraName: 'Nursery'),
        _evt(
            type: HealthEventType.alertFired,
            tsMs: 3000,
            cameraName: 'Nursery'),
        _evt(
            type: HealthEventType.zombieDetected,
            tsMs: 4000,
            cameraName: 'Nursery',
            detail: 'PTS stall + buffering stuck'),
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
