// 260514-siv: HealthSummaryScreen now takes a Session parameter instead of
// reading healthEventsProvider. The tests below were rewritten to construct
// Session fixtures directly. The old test that asserted on the in-flight
// "Monitoring just started" / "Session uptime" copy is replaced by tests on
// the new Session-driven empty / non-empty render paths.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rtsp_mixer/core/theme/app_theme.dart';
import 'package:rtsp_mixer/features/monitoring/models/health_event.dart';
import 'package:rtsp_mixer/features/monitoring/models/session.dart';
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

Session _session({
  required List<HealthEvent> events,
  DateTime? startedAt,
  DateTime? endedAt,
  List<({String id, String name})> cameras = const [],
}) {
  return Session(
    id: 'test-id',
    startedAt: startedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
    endedAt: endedAt,
    events: events,
    cameras: cameras,
  );
}

Future<void> _pumpSummary(
  WidgetTester tester,
  Session session,
) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: AppTheme.dark,
        home: HealthSummaryScreen(session: session),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  group('HealthSummaryScreen (MNTR-01, 260514-siv)', () {
    testWidgets('empty session renders empty-events state', (tester) async {
      await _pumpSummary(tester, _session(events: const []));
      expect(find.text('No events recorded'), findsOneWidget);
      expect(find.byIcon(Icons.health_and_safety_outlined), findsOneWidget);
    });

    testWidgets('in-flight session shows "Session uptime" label',
        (tester) async {
      await _pumpSummary(
        tester,
        _session(
          events: [
            _evt(type: HealthEventType.monitoringStarted, tsMs: 1000),
          ],
        ),
      );
      expect(find.text('Session uptime'), findsOneWidget);
    });

    testWidgets('finalized session shows "Session duration" label',
        (tester) async {
      await _pumpSummary(
        tester,
        _session(
          events: [
            _evt(type: HealthEventType.monitoringStarted, tsMs: 0),
            _evt(type: HealthEventType.monitoringStopped, tsMs: 1000),
          ],
          startedAt: DateTime.fromMillisecondsSinceEpoch(0),
          endedAt: DateTime.fromMillisecondsSinceEpoch(1000),
        ),
      );
      expect(find.text('Session duration'), findsOneWidget);
    });

    testWidgets('events list renders newest-on-top', (tester) async {
      await _pumpSummary(
        tester,
        _session(events: [
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
        ]),
      );
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
        'finalized banner appears when session.endedAt is set',
        (tester) async {
      await _pumpSummary(
        tester,
        _session(
          events: [
            _evt(type: HealthEventType.monitoringStarted, tsMs: 1000),
            _evt(type: HealthEventType.monitoringStopped, tsMs: 2000),
          ],
          endedAt: DateTime.fromMillisecondsSinceEpoch(2000),
        ),
      );
      expect(find.text('Session finalized.'), findsOneWidget);
    });

    testWidgets('event with null cameraName renders as "Session"',
        (tester) async {
      await _pumpSummary(
        tester,
        _session(events: [
          _evt(type: HealthEventType.wifiDropped, tsMs: 1000),
        ]),
      );
      // Row text is "HH:mm:ss · Session · WiFi lost"
      expect(find.textContaining('Session'), findsWidgets);
      expect(find.textContaining('WiFi lost'), findsOneWidget);
    });

    testWidgets('event row shows correct label copy for each event type',
        (tester) async {
      await _pumpSummary(
        tester,
        _session(events: [
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
        ]),
      );
      expect(find.textContaining('Reconnect attempt'), findsOneWidget);
      expect(find.textContaining('Reconnected'), findsOneWidget);
      expect(find.textContaining('5-minute alert sent'), findsOneWidget);
      expect(find.textContaining('Zombie stream detected'), findsOneWidget);
      // detail rendered on its own line
      expect(find.text('PTS stall + buffering stuck'), findsOneWidget);
    });
  });
}
