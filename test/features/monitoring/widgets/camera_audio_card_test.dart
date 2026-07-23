import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rtsp_mixer/core/theme/app_theme.dart';
import 'package:rtsp_mixer/features/monitoring/models/player_state.dart';
import 'package:rtsp_mixer/features/monitoring/widgets/camera_audio_card.dart';

Future<void> _pumpCard(
  WidgetTester tester,
  CameraAudioState state,
) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: CameraAudioCard(
            cameraState: state,
            cameraIndex: 0,
            showVideoPreview: false,
            showDebugInfo: false,
            activityThreshold: 0.1,
            onToggleVideo: () {},
          ),
        ),
      ),
    ),
  );
  // Let riverpod + animated containers settle. Use a bounded pump instead of
  // pumpAndSettle to avoid hanging on the activity-border animation.
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  const reconnecting = CameraAudioState(
    cameraId: 'cam1',
    cameraName: 'Nursery',
    connectionStatus: CameraConnectionStatus.reconnecting,
  );
  const connecting = CameraAudioState(
    cameraId: 'cam1',
    cameraName: 'Nursery',
    connectionStatus: CameraConnectionStatus.connecting,
  );
  const error = CameraAudioState(
    cameraId: 'cam1',
    cameraName: 'Nursery',
    connectionStatus: CameraConnectionStatus.error,
    errorMessage: 'Stream failed',
  );
  const playing = CameraAudioState(
    cameraId: 'cam1',
    cameraName: 'Nursery',
    connectionStatus: CameraConnectionStatus.playing,
  );
  const playingMuted = CameraAudioState(
    cameraId: 'cam1',
    cameraName: 'Nursery',
    connectionStatus: CameraConnectionStatus.playing,
    isMuted: true,
  );
  const playingWithHistory = CameraAudioState(
    cameraId: 'cam1',
    cameraName: 'Nursery',
    connectionStatus: CameraConnectionStatus.playing,
    levelHistory: [0.1, 0.5, 0.9, 0.3],
  );
  const playingQuiet = CameraAudioState(
    cameraId: 'cam1',
    cameraName: 'Nursery',
    connectionStatus: CameraConnectionStatus.playing,
    audioLevel: 0.02,
  );

  final bannerFinder = find.byKey(const ValueKey('status-banner'));
  final waveformFinder = find.byKey(const ValueKey('waveform-chart'));

  group('CameraAudioCard reconnecting state (RELY-02 / D-10 / D-11)', () {
    testWidgets('renders a CircularProgressIndicator spinner', (tester) async {
      await _pumpCard(tester, reconnecting);
      expect(find.byType(CircularProgressIndicator), findsWidgets);
    });

    testWidgets('renders "Reconnecting…" text (U+2026 ellipsis)', (tester) async {
      await _pumpCard(tester, reconnecting);
      expect(find.text('Reconnecting…'), findsOneWidget);
    });

    testWidgets('does NOT render LinearProgressIndicator', (tester) async {
      await _pumpCard(tester, reconnecting);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('contains NO attempt/retry/countdown copy (D-11)', (tester) async {
      await _pumpCard(tester, reconnecting);
      final forbidden = RegExp(r'attempt|retry|countdown', caseSensitive: false);
      final textWidgets = find.byType(Text).evaluate();
      for (final elem in textWidgets) {
        final widget = elem.widget as Text;
        final data = widget.data ?? '';
        expect(
          forbidden.hasMatch(data),
          isFalse,
          reason: 'D-11 forbids attempt/retry/countdown on card — found: "$data"',
        );
      }
    });
  });

  group('CameraAudioCard status banner slot (problem states only)', () {
    testWidgets('reconnecting renders the banner slot', (tester) async {
      await _pumpCard(tester, reconnecting);
      expect(bannerFinder, findsOneWidget);
    });

    testWidgets('error renders the banner slot', (tester) async {
      await _pumpCard(tester, error);
      expect(bannerFinder, findsOneWidget);
    });

    testWidgets('playing renders NO banner slot', (tester) async {
      await _pumpCard(tester, playing);
      expect(bannerFinder, findsNothing);
    });

    testWidgets('connecting renders NO banner slot', (tester) async {
      await _pumpCard(tester, connecting);
      expect(bannerFinder, findsNothing);
    });
  });

  group('CameraAudioCard muted clarity', () {
    testWidgets('muted playing shows "Muted" and the volume-off icon',
        (tester) async {
      await _pumpCard(tester, playingMuted);
      expect(find.text('Muted'), findsOneWidget);
      expect(find.byIcon(Icons.volume_off), findsOneWidget);
    });

    testWidgets('un-muted playing shows a % value, not "Muted"',
        (tester) async {
      await _pumpCard(tester, playing);
      expect(find.text('100%'), findsOneWidget);
      expect(find.text('Muted'), findsNothing);
    });
  });

  group('CameraAudioCard state-transition animations (regression guard)', () {
    testWidgets('playing state wires AnimatedSwitchers (status line + volume)',
        (tester) async {
      await _pumpCard(tester, playing);
      // At minimum the status-line crossfade and the volume-text crossfade are
      // present; the connecting/slider swap adds a third. Fade-only switchers
      // keep child layout size stable so the bounded pump finders stay valid.
      expect(find.byType(AnimatedSwitcher), findsWidgets);
    });

    testWidgets('reconnecting keeps the banner findsOneWidget after pump',
        (tester) async {
      await _pumpCard(tester, reconnecting);
      expect(bannerFinder, findsOneWidget);
      expect(find.byType(AnimatedSwitcher), findsWidgets);
    });

    testWidgets('error keeps the banner findsOneWidget after pump',
        (tester) async {
      await _pumpCard(tester, error);
      expect(bannerFinder, findsOneWidget);
    });

    testWidgets('muted state resolves "Muted" to exactly one Text after pump',
        (tester) async {
      await _pumpCard(tester, playingMuted);
      expect(find.text('Muted'), findsOneWidget);
    });
  });

  group('CameraAudioCard waveform chart (quick-260723-sph)', () {
    testWidgets('live camera with level history renders the waveform chart',
        (tester) async {
      await _pumpCard(tester, playingWithHistory);
      expect(waveformFinder, findsOneWidget);
    });

    testWidgets('non-live (connecting) camera renders NO waveform chart',
        (tester) async {
      await _pumpCard(tester, connecting);
      expect(waveformFinder, findsNothing);
    });
  });

  group('CameraAudioCard level bar color (quick-260723-sph)', () {
    testWidgets(
        'low absolute level on a healthy live stream stays green, not amber',
        (tester) async {
      // A low absolute level is a normally quiet nursery, not a degraded
      // state — an amber branch here would glow all night. This test pins
      // the removed-amber-branch decision so a refactor can't silently
      // reintroduce a nightly amber glow.
      await _pumpCard(tester, playingQuiet);
      final indicator = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      final valueColor =
          (indicator.valueColor as AlwaysStoppedAnimation<Color?>).value;
      expect(valueColor, AppTheme.statusOnline);
      expect(valueColor, isNot(Colors.amber));
    });
  });

  group('CameraAudioCard connecting state (regression guard)', () {
    testWidgets('renders LinearProgressIndicator', (tester) async {
      await _pumpCard(tester, connecting);
      expect(find.byType(LinearProgressIndicator), findsWidgets);
    });

    testWidgets('renders "Connecting…" text (U+2026, not three ASCII dots)', (tester) async {
      await _pumpCard(tester, connecting);
      expect(find.text('Connecting…'), findsOneWidget);
      expect(find.text('Connecting...'), findsNothing);
    });
  });
}
