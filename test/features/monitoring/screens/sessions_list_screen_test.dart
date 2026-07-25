import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rtsp_mixer/core/theme/app_theme.dart';
import 'package:rtsp_mixer/features/monitoring/models/player_state.dart';
import 'package:rtsp_mixer/features/monitoring/models/session.dart';
import 'package:rtsp_mixer/features/monitoring/providers/audio_player_provider.dart';
import 'package:rtsp_mixer/features/monitoring/providers/session_history_provider.dart';
import 'package:rtsp_mixer/features/monitoring/screens/sessions_list_screen.dart';

/// Test doubles — stub build() so no disk or players are touched.
class _FakeSessionHistory extends SessionHistoryNotifier {
  _FakeSessionHistory(this.seed);
  final SessionHistory seed;

  @override
  Future<SessionHistory> build() async => seed;
}

class _FakeAudio extends AudioPlayerNotifier {
  _FakeAudio(this.seed);
  final MonitoringState seed;

  @override
  Future<MonitoringState> build() async => seed;
}

CameraAudioState _cam(CameraConnectionStatus status, {String id = 'cam1'}) =>
    CameraAudioState(
      cameraId: id,
      cameraName: 'Nursery',
      connectionStatus: status,
      activeQuality: 'low',
      availableQualities: const {'low': 'a'},
    );

Session _liveSession() => Session(
      id: 'sess-1',
      startedAt: DateTime.now().subtract(const Duration(minutes: 3)),
      endedAt: null,
      events: const [],
      cameras: const [(id: 'cam1', name: 'Nursery')],
    );

Session _pastSession() => Session(
      id: 'sess-0',
      startedAt: DateTime.now().subtract(const Duration(hours: 2)),
      endedAt: DateTime.now().subtract(const Duration(hours: 1)),
      events: const [],
      cameras: const [(id: 'cam1', name: 'Nursery')],
    );

Future<void> _pumpList(
  WidgetTester tester, {
  required List<CameraAudioState> cameras,
  bool withCurrent = true,
  List<Session> past = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sessionHistoryProvider.overrideWith(
          () => _FakeSessionHistory(
            SessionHistory(
              current: withCurrent ? _liveSession() : null,
              past: past,
            ),
          ),
        ),
        audioPlayerProvider
            .overrideWith(() => _FakeAudio(MonitoringState(cameras: cameras))),
      ],
      child: MaterialApp(
        theme: AppTheme.dark,
        home: const SessionsListScreen(),
      ),
    ),
  );
  // Two frames: the AsyncNotifiers resolve between the first and the second.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  // The live row's badge is a health claim, not just "a session exists" — an
  // "In progress" chip over a failed mix is exactly the lie a parent would
  // sleep through.
  group('live session badge', () {
    testWidgets('all-live mix reads "In progress"', (tester) async {
      await _pumpList(tester, cameras: [_cam(CameraConnectionStatus.playing)]);
      expect(find.text('In progress'), findsOneWidget);
    });

    testWidgets('reconnecting mix reads "Reconnecting…"', (tester) async {
      await _pumpList(
        tester,
        cameras: [_cam(CameraConnectionStatus.reconnecting)],
      );
      expect(find.text('In progress'), findsNothing);
      expect(find.text('Reconnecting…'), findsOneWidget);
    });

    testWidgets('a failed camera reads "Stream failed"', (tester) async {
      await _pumpList(
        tester,
        cameras: [
          _cam(CameraConnectionStatus.playing),
          _cam(CameraConnectionStatus.error, id: 'cam2'),
        ],
      );
      expect(find.text('In progress'), findsNothing);
      expect(find.text('Stream failed'), findsOneWidget);
    });

    testWidgets('a still-connecting camera reads "Connecting…"',
        (tester) async {
      await _pumpList(
        tester,
        cameras: [_cam(CameraConnectionStatus.connecting)],
      );
      expect(find.text('In progress'), findsNothing);
      expect(find.text('Connecting…'), findsOneWidget);
    });

    testWidgets('finalized rows carry no badge at all', (tester) async {
      await _pumpList(
        tester,
        cameras: const [],
        withCurrent: false,
        past: [_pastSession()],
      );
      expect(find.text('In progress'), findsNothing);
      expect(find.text('Connecting…'), findsNothing);
      expect(find.text('Reconnecting…'), findsNothing);
      expect(find.text('Stream failed'), findsNothing);
      // The finalized row itself still renders.
      expect(find.text('Duration'), findsOneWidget);
    });
  });
}
