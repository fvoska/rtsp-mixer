import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rtsp_mixer/core/providers/settings_provider.dart';
import 'package:rtsp_mixer/core/theme/app_theme.dart';
import 'package:rtsp_mixer/features/settings/screens/settings_screen.dart';

import '../../support/logging.dart';

/// The Appearance section's OLED switch: that it is present, reflects and
/// writes the setting, and — because it is a property of the *dark* theme
/// rather than a mode of its own — tells the truth about when it takes effect.
void main() {
  installAppLoggerTestIsolation();

  late ProviderContainer container;

  Future<void> pumpSettings(WidgetTester tester, ThemeData theme) async {
    container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: theme, home: const SettingsScreen()),
      ),
    );
    await tester.pump();
  }

  Finder oledSwitch() => find.ancestor(
        of: find.text('OLED black'),
        matching: find.byType(SwitchListTile),
      );

  testWidgets('is off by default and turns on when tapped', (tester) async {
    await pumpSettings(tester, AppTheme.dark);

    expect(oledSwitch(), findsOneWidget);
    expect(container.read(settingsProvider).oledDark, isFalse);

    await tester.tap(find.text('OLED black'));
    await tester.pump();

    expect(container.read(settingsProvider).oledDark, isTrue);
    expect(
      tester.widget<SwitchListTile>(oledSwitch()).value,
      isTrue,
      reason: 'the switch must reflect the stored preference',
    );
  });

  testWidgets('explains the OLED win when dark is on screen', (tester) async {
    await pumpSettings(tester, AppTheme.dark);
    await tester.tap(find.text('OLED black'));
    await tester.pump();

    expect(find.textContaining('emits no light on OLED'), findsOneWidget);
    expect(find.textContaining('Applies once dark mode is active'), findsNothing);
  });

  testWidgets('says the flip is pending while light is on screen',
      (tester) async {
    // The switch stays usable under light — the copy is what keeps that from
    // reading as a broken toggle.
    await pumpSettings(tester, AppTheme.light);
    await tester.tap(find.text('OLED black'));
    await tester.pump();

    expect(container.read(settingsProvider).oledDark, isTrue);
    expect(
      find.textContaining('Applies once dark mode is active'),
      findsOneWidget,
    );
  });

  testWidgets('sits with the theme picker in Appearance, not elsewhere',
      (tester) async {
    await pumpSettings(tester, AppTheme.dark);
    // Ordering matters for discoverability: the OLED switch only makes sense
    // directly under the System/Light/Dark control it qualifies.
    final picker = tester.getTopLeft(find.byType(SegmentedButton<ThemeMode>));
    final toggle = tester.getTopLeft(oledSwitch());
    expect(toggle.dy, greaterThan(picker.dy));
    expect(
      toggle.dy,
      lessThan(tester.getTopLeft(find.text('Use plain RTSP')).dy),
    );
  });
}
