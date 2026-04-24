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
