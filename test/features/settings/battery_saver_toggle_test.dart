import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rtsp_mixer/core/providers/settings_provider.dart';
import 'package:rtsp_mixer/core/theme/app_theme.dart';
import 'package:rtsp_mixer/features/settings/screens/settings_screen.dart';

import '../../support/logging.dart';

/// The battery saver switch in Settings: present, reflects and writes the
/// setting, and sits above the audio-buffer section so it's easy to find
/// without digging into Connection settings.
void main() {
  installAppLoggerTestIsolation();

  late ProviderContainer container;

  Future<void> pumpSettings(WidgetTester tester) async {
    container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: AppTheme.dark, home: const SettingsScreen()),
      ),
    );
    await tester.pump();
  }

  Finder batterySaverSwitch() => find.ancestor(
        of: find.text('Battery saver'),
        matching: find.byType(SwitchListTile),
      );

  testWidgets('is off by default and turns on when tapped', (tester) async {
    await pumpSettings(tester);

    expect(batterySaverSwitch(), findsOneWidget);
    expect(container.read(settingsProvider).batterySaverMode, isFalse);

    await tester.tap(find.text('Battery saver'));
    await tester.pump();

    expect(container.read(settingsProvider).batterySaverMode, isTrue);
    expect(
      tester.widget<SwitchListTile>(batterySaverSwitch()).value,
      isTrue,
      reason: 'the switch must reflect the stored preference',
    );
  });

  testWidgets('subtitle describes the effect once enabled', (tester) async {
    await pumpSettings(tester);
    await tester.tap(find.text('Battery saver'));
    await tester.pump();

    expect(
      find.textContaining('audio streaming and auto-reconnect keep running'),
      findsOneWidget,
    );
  });

  testWidgets('sits above the audio buffer section', (tester) async {
    await pumpSettings(tester);
    final toggle = tester.getTopLeft(batterySaverSwitch());
    final audioBuffer = tester.getTopLeft(find.text('Audio buffer'));
    expect(toggle.dy, lessThan(audioBuffer.dy));
  });
}
