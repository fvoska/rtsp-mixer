import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rtsp_mixer/core/theme/app_theme.dart';
import 'package:rtsp_mixer/features/monitoring/models/player_state.dart';
import 'package:rtsp_mixer/features/monitoring/widgets/camera_audio_card.dart';

/// Light mode is brand new — nothing else in the suite renders under it. This
/// pins that the busiest widget in the app actually builds in both themes.
void main() {
  const states = <String, CameraAudioState>{
    'live': CameraAudioState(
      cameraId: 'c',
      cameraName: 'Nursery',
      connectionStatus: CameraConnectionStatus.playing,
      audioActivity: 0.8,
      levelHistory: [0.2, 0.7, 0.4],
      availableQualities: {'high': 'a', 'low': 'b'},
      activeQuality: 'high',
    ),
    'reconnecting': CameraAudioState(
      cameraId: 'c',
      cameraName: 'Nursery',
      connectionStatus: CameraConnectionStatus.reconnecting,
    ),
    'error': CameraAudioState(
      cameraId: 'c',
      cameraName: 'Nursery',
      connectionStatus: CameraConnectionStatus.error,
      errorMessage: 'Stream failed',
    ),
  };

  for (final theme in {
    'light': AppTheme.light,
    'dark': AppTheme.dark,
    'darkOled': AppTheme.darkOled,
  }.entries) {
    for (final state in states.entries) {
      testWidgets('${state.key} card builds cleanly under ${theme.key}',
          (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: theme.value,
              home: Scaffold(
                body: SingleChildScrollView(
                  child: CameraAudioCard(
                    cameraState: state.value,
                    cameraIndex: 0,
                    showDebugInfo: true,
                    onToggleVideo: () {},
                    onRemove: () {},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 50));
        expect(tester.takeException(), isNull);
      });
    }
  }
}
