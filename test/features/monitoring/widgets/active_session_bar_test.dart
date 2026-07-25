import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rtsp_mixer/core/theme/app_theme.dart';
import 'package:rtsp_mixer/features/auth/models/auth_state.dart';
import 'package:rtsp_mixer/features/auth/providers/auth_provider.dart';
import 'package:rtsp_mixer/features/monitoring/models/player_state.dart';
import 'package:rtsp_mixer/features/monitoring/models/session.dart';
import 'package:rtsp_mixer/features/monitoring/providers/audio_player_provider.dart';
import 'package:rtsp_mixer/features/monitoring/providers/session_history_provider.dart';
import 'package:rtsp_mixer/features/monitoring/widgets/active_session_bar.dart';

/// Test double — returns a pre-seeded SessionHistory without touching disk.
class _FakeSessionHistoryNotifier extends SessionHistoryNotifier {
  _FakeSessionHistoryNotifier(this.seed);
  final SessionHistory seed;

  @override
  Future<SessionHistory> build() async => seed;
}

/// Test double — returns a pre-seeded MonitoringState without opening players.
/// The bar reads it to decide whether "Monitoring · uptime" is honest, so every
/// pump seeds an explicit per-camera health.
class _FakeAudioNotifier extends AudioPlayerNotifier {
  _FakeAudioNotifier(this.seed);
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

/// Test double — returns a pre-seeded AuthState without touching storage.
class _FakeAuthNotifier extends AuthNotifier {
  _FakeAuthNotifier(this.seed);
  final AuthState seed;

  @override
  Future<AuthState> build() async => seed;
}

Future<void> _pumpBar(
  WidgetTester tester, {
  required int selectedIndex,
  Session? currentSession,
  bool resumeMonitoring = false,
  List<CameraAudioState>? cameras,
}) async {
  // Default to an all-live mix so the bar's healthy copy is the baseline; the
  // degraded cases pass their own camera states.
  final mix = cameras ??
      (currentSession == null
          ? const <CameraAudioState>[]
          : [_cam(CameraConnectionStatus.playing)]);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sessionHistoryProvider.overrideWith(
          () => _FakeSessionHistoryNotifier(
            SessionHistory(current: currentSession, past: const []),
          ),
        ),
        audioPlayerProvider.overrideWith(
          () => _FakeAudioNotifier(MonitoringState(cameras: mix)),
        ),
        authNotifierProvider.overrideWith(
          () => _FakeAuthNotifier(
            AuthState.authenticated(
              host: '10.0.0.1',
              resumeMonitoring: resumeMonitoring,
            ),
          ),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ActiveSessionBar(selectedIndex: selectedIndex),
          ),
        ),
      ),
    ),
  );
  // Let the AsyncNotifiers settle.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

/// A session that renders as "7m" of uptime.
///
/// ActiveSessionBar reads `DateTime.now()` when it builds and again on every
/// 1s tick, so the age of this fixture is real elapsed time, not a fixed
/// value. Anchoring it 7m30s back rather than exactly 7m puts it in the middle
/// of the minute bucket: `Duration.inMinutes` floors, so any drift within ±30s
/// between constructing the fixture and rendering it still formats as "7m".
/// At exactly 7m the fixture sat on the bucket edge with zero slack.
Session _liveSession() => Session(
      id: 'sess-1',
      startedAt: DateTime.now().subtract(
        const Duration(minutes: 7, seconds: 30),
      ),
      endedAt: null,
      events: const [],
      cameras: const [(id: 'cam1', name: 'Nursery')],
    );

void main() {
  group('ActiveSessionBar visibility', () {
    testWidgets('hidden on Monitor tab even when a session is active',
        (tester) async {
      await _pumpBar(
        tester,
        selectedIndex: 0,
        currentSession: _liveSession(),
      );
      expect(find.textContaining('Monitoring'), findsNothing);
    });

    testWidgets('hidden when no session and no resume pending', (tester) async {
      await _pumpBar(tester, selectedIndex: 1);
      expect(find.textContaining('Monitoring'), findsNothing);
    });

    testWidgets('shown with uptime when a session is active on non-monitor tab',
        (tester) async {
      await _pumpBar(
        tester,
        selectedIndex: 1,
        currentSession: _liveSession(),
      );
      // Uptime format is "7m" for a 7-minute-old session.
      expect(find.text('Monitoring · 7m', findRichText: true), findsOneWidget);
    });

    testWidgets(
        'shows "resuming…" when auth signals resume but session not yet set',
        (tester) async {
      // Relaunch race: was_monitoring=true is on disk, auth has surfaced it
      // via resumeMonitoring, but SessionHistoryNotifier.beginSession hasn't
      // run yet. The user must still see the bar so they can tap-to-return.
      await _pumpBar(
        tester,
        selectedIndex: 1,
        resumeMonitoring: true,
      );
      expect(find.text('Monitoring · resuming…', findRichText: true), findsOneWidget);
    });

    testWidgets(
        'resume flag is ignored on Monitor tab (inline banner takes over)',
        (tester) async {
      await _pumpBar(
        tester,
        selectedIndex: 0,
        resumeMonitoring: true,
      );
      expect(find.textContaining('Monitoring'), findsNothing);
    });

    testWidgets('actual session beats resume flag (uptime not "resuming…")',
        (tester) async {
      await _pumpBar(
        tester,
        selectedIndex: 2,
        currentSession: _liveSession(),
        resumeMonitoring: true,
      );
      expect(find.text('Monitoring · resuming…', findRichText: true), findsNothing);
      expect(find.text('Monitoring · 7m', findRichText: true), findsOneWidget);
    });
  });

  // The bar must never claim audio is flowing while it isn't: the reassuring
  // "Monitoring · uptime" copy belongs to an all-live mix only.
  group('ActiveSessionBar honesty', () {
    testWidgets('says "Reconnecting…" while a camera is reconnecting',
        (tester) async {
      await _pumpBar(
        tester,
        selectedIndex: 1,
        currentSession: _liveSession(),
        cameras: [_cam(CameraConnectionStatus.reconnecting)],
      );
      expect(find.text('Reconnecting…', findRichText: true), findsOneWidget);
      expect(find.textContaining('Monitoring ·'), findsNothing);
    });

    testWidgets('says "Stream failed" when a camera errored', (tester) async {
      await _pumpBar(
        tester,
        selectedIndex: 1,
        currentSession: _liveSession(),
        cameras: [
          _cam(CameraConnectionStatus.playing),
          _cam(CameraConnectionStatus.error, id: 'cam2'),
        ],
      );
      expect(find.text('Stream failed', findRichText: true), findsOneWidget);
      expect(find.textContaining('Monitoring ·'), findsNothing);
    });

    testWidgets('says "Connecting…" before the first stream is live',
        (tester) async {
      await _pumpBar(
        tester,
        selectedIndex: 1,
        currentSession: _liveSession(),
        cameras: [_cam(CameraConnectionStatus.connecting)],
      );
      expect(find.text('Connecting…', findRichText: true), findsOneWidget);
      expect(find.textContaining('Monitoring ·'), findsNothing);
    });
  });
}
