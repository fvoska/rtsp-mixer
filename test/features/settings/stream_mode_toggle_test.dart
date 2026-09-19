import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rtsp_mixer/core/providers/settings_provider.dart';
import 'package:rtsp_mixer/core/theme/app_theme.dart';
import 'package:rtsp_mixer/features/settings/screens/settings_screen.dart';

import '../../support/logging.dart';

/// The stream mode control in Settings: Realtime by default, Buffered
/// reveals the delay slider, and both write through to the setting.
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

  Future<void> reveal(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
  }

  testWidgets('defaults to Realtime with the delay slider hidden',
      (tester) async {
    await pumpSettings(tester);
    await reveal(tester, find.text('Stream mode'));

    expect(container.read(settingsProvider).streamMode, StreamMode.realtime);
    expect(find.byType(SegmentedButton<StreamMode>), findsOneWidget);
    expect(find.textContaining('Realtime — lowest delay'), findsOneWidget);
    expect(find.text('Buffer delay'), findsNothing);
  });

  testWidgets('switching to Buffered persists and reveals the delay slider',
      (tester) async {
    await pumpSettings(tester);
    await reveal(tester, find.text('Stream mode'));

    await tester.tap(find.text('Buffered'));
    await tester.pump();

    expect(container.read(settingsProvider).streamMode, StreamMode.buffered);
    await reveal(tester, find.text('Buffer delay'));
    expect(find.text('Buffer delay'), findsOneWidget);
    expect(find.textContaining('2.0 s'), findsWidgets);

    // Back to Realtime hides it again. The list builds lazily, so scroll
    // back up before looking for the segmented control.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 800));
    await tester.pump();
    await reveal(tester, find.text('Realtime'));
    await tester.tap(find.text('Realtime'));
    await tester.pump();
    expect(container.read(settingsProvider).streamMode, StreamMode.realtime);
    expect(find.text('Buffer delay'), findsNothing);
  });

  testWidgets('the delay slider writes the setting in half-second steps',
      (tester) async {
    await pumpSettings(tester);
    await reveal(tester, find.text('Stream mode'));
    await tester.tap(find.text('Buffered'));
    await tester.pump();
    await reveal(tester, find.text('Buffer delay'));

    final slider = find.byWidgetPredicate(
      (w) => w is Slider && w.max == kMaxBufferedDelaySeconds,
    );
    expect(slider, findsOneWidget);
    // Drag well to the right: lands on the maximum.
    await tester.drag(slider, const Offset(400, 0));
    await tester.pump();

    final value = container.read(settingsProvider).bufferedDelaySeconds;
    expect(value, kMaxBufferedDelaySeconds);
    expect((value * 2).round() / 2.0, value, reason: 'snapped to 0.5 s');
  });

  testWidgets('keeps the audio buffer slider (a different buffer)',
      (tester) async {
    await pumpSettings(tester);
    await reveal(tester, find.text('Audio buffer'));
    expect(find.text('Audio buffer'), findsOneWidget);
  });
}
