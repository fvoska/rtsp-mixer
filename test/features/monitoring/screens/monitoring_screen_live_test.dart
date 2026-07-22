import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rtsp_mixer/features/auth/models/auth_state.dart';
import 'package:rtsp_mixer/features/auth/providers/auth_provider.dart';
import 'package:rtsp_mixer/features/monitoring/models/player_state.dart';
import 'package:rtsp_mixer/features/monitoring/models/session.dart';
import 'package:rtsp_mixer/features/monitoring/providers/audio_player_provider.dart';
import 'package:rtsp_mixer/features/monitoring/providers/session_history_provider.dart';
import 'package:rtsp_mixer/features/monitoring/screens/monitoring_screen.dart';

// Fakes: stub each notifier's build() so no platform channels / disk / players
// are touched. build() overrides drop the real side effects (ref.listen /
// onDispose / secure storage) which are irrelevant to rendering the live view.
class _FakeAudio extends AudioPlayerNotifier {
  _FakeAudio(this._s);
  final MonitoringState _s;
  @override
  Future<MonitoringState> build() async => _s;
}

class _FakeSession extends SessionHistoryNotifier {
  _FakeSession(this._h);
  final SessionHistory _h;
  @override
  Future<SessionHistory> build() async => _h;
}

class _FakeAuth extends AuthNotifier {
  @override
  Future<AuthState> build() async =>
      AuthState.authenticated(host: 'h', resumeMonitoring: false);
}

Future<void> _pumpLive(
  WidgetTester tester,
  List<CameraAudioState> cams, {
  double widthDp = 800,
}) async {
  tester.view.physicalSize = Size(widthDp * 2, 2000);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(() => tester.view.reset());

  final session = Session.start(
    cameras: cams.map((c) => (id: c.cameraId, name: c.cameraName)).toList(),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        audioPlayerProvider
            .overrideWith(() => _FakeAudio(MonitoringState(cameras: cams))),
        sessionHistoryProvider
            .overrideWith(() => _FakeSession(SessionHistory(current: session))),
        authNotifierProvider.overrideWith(() => _FakeAuth()),
      ],
      child: const MaterialApp(home: MonitoringScreen()),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  // Regression: the live monitoring view must render without throwing. A
  // previous version typed _LiveMonitoringView.monitoringState as the untyped
  // `AsyncValue`, so `state` was dynamic and the showSourceBadge computation
  // `state.cameras.any((c) => c.isManual)` threw a runtime TypeError
  // ((dynamic)=>dynamic is not a subtype of (CameraAudioState)=>bool),
  // painting the whole body as a gray RenderErrorBox while audio kept playing.
  const fiona = CameraAudioState(
    cameraId: 'fiona',
    cameraName: 'Fiona',
    connectionStatus: CameraConnectionStatus.playing,
    activeQuality: 'low',
    activeStreamUrl: 'rtsps://x/low',
    availableQualities: {'low': 'a', 'medium': 'b', 'high': 'c'},
  );
  const porch = CameraAudioState(
    cameraId: 'porch',
    cameraName: 'Porch',
    connectionStatus: CameraConnectionStatus.playing,
    activeQuality: 'high',
    activeStreamUrl: 'rtsps://x/high',
    availableQualities: {'high': 'c'},
  );

  testWidgets('renders two live Unifi cameras without throwing', (tester) async {
    await _pumpLive(tester, [fiona, porch]);
    expect(tester.takeException(), isNull);
    expect(find.text('Fiona'), findsOneWidget);
    expect(find.text('Porch'), findsOneWidget);
    // No gray RenderErrorBox in the body.
    expect(find.byType(ErrorWidget), findsNothing);
  });

  testWidgets('renders a mixed Unifi + manual mix without throwing',
      (tester) async {
    const manual = CameraAudioState(
      cameraId: 'manual',
      cameraName: 'Nursery',
      connectionStatus: CameraConnectionStatus.playing,
      activeQuality: 'stream',
      activeStreamUrl: 'rtsp://192.168.1.50:554/stream',
      availableQualities: {'stream': 'rtsp://192.168.1.50:554/stream'},
      isManual: true,
    );
    await _pumpLive(tester, [fiona, manual]);
    expect(tester.takeException(), isNull);
    expect(find.byType(ErrorWidget), findsNothing);
  });

  testWidgets('tolerates a camera with a blank quality key', (tester) async {
    const blank = CameraAudioState(
      cameraId: 'blank',
      cameraName: 'Blank',
      connectionStatus: CameraConnectionStatus.playing,
      activeQuality: '',
      activeStreamUrl: 'rtsps://x/blank',
      availableQualities: {'': 'a'},
    );
    await _pumpLive(tester, [blank]);
    expect(tester.takeException(), isNull);
    expect(find.byType(ErrorWidget), findsNothing);
  });

  // Regression: the live-view toolbar ("Cameras" + Show details / Show video)
  // overflowed on a phone-width card. It must collapse to icon-only toggles
  // instead of overflowing.
  for (final w in [340.0, 360.0, 411.0]) {
    testWidgets('live toolbar + cards fit at ${w}dp (2 cameras)',
        (tester) async {
      await _pumpLive(tester, [fiona, porch], widthDp: w);
      expect(tester.takeException(), isNull);
      expect(find.byType(ErrorWidget), findsNothing);
    });
  }

  testWidgets('live toolbar fits at 360dp with the >2-camera warning',
      (tester) async {
    const third = CameraAudioState(
      cameraId: 'third',
      cameraName: 'Backyard',
      connectionStatus: CameraConnectionStatus.playing,
      activeQuality: 'low',
      availableQualities: {'low': 'a'},
    );
    await _pumpLive(tester, [fiona, porch, third], widthDp: 360);
    expect(tester.takeException(), isNull);
    expect(find.byType(ErrorWidget), findsNothing);
  });
}
