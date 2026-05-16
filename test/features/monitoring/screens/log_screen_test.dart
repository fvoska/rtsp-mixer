import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rtsp_mixer/core/theme/app_theme.dart';
import 'package:rtsp_mixer/features/monitoring/screens/log_screen.dart';

Future<void> _pumpLogs(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: const LogScreen(),
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  group('LogScreen header (consistency refactor)', () {
    testWidgets('AppBar title is the static "Logs" — no dynamic count',
        (tester) async {
      // Dynamic counts ("Logs (123)") cause the title's width to shift as
      // entries are appended, which makes the AppBar look subtly different
      // from the other tabs. The count moved off the title.
      await _pumpLogs(tester);
      expect(find.widgetWithText(AppBar, 'Logs'), findsOneWidget);
      expect(
        find.byWidgetPredicate((w) {
          if (w is! Text) return false;
          final s = w.data ?? '';
          return s.startsWith('Logs (');
        }),
        findsNothing,
      );
    });

    testWidgets('AppBar has no PreferredSize bottom strip', (tester) async {
      // The filter TextField used to live in AppBar.bottom via PreferredSize,
      // making the Logs AppBar taller than every other tab. It now sits in
      // the body so the header height is identical across tabs.
      await _pumpLogs(tester);
      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.bottom, isNull);
    });

    testWidgets('header has a single PopupMenuButton instead of two icons',
        (tester) async {
      // Auto-scroll + copy-to-clipboard collapsed into one overflow menu so
      // the action area matches the other tabs (none → at most one trailing).
      // PopupMenuButton is generic over a private enum, so we match by
      // runtimeType-name rather than the strongly-typed `byType`.
      await _pumpLogs(tester);
      final popupFinder = find.byWidgetPredicate(
        (w) => w.runtimeType.toString().startsWith('PopupMenuButton'),
      );
      expect(
        find.descendant(of: find.byType(AppBar), matching: popupFinder),
        findsOneWidget,
      );
    });

    testWidgets('filter TextField is rendered in the body, not the AppBar',
        (tester) async {
      await _pumpLogs(tester);
      final filter = find.byType(TextField);
      expect(filter, findsOneWidget);
      // The TextField must NOT be a descendant of the AppBar widget.
      expect(
        find.descendant(of: find.byType(AppBar), matching: filter),
        findsNothing,
      );
    });

    testWidgets('overflow menu exposes both auto-scroll and copy actions',
        (tester) async {
      await _pumpLogs(tester);
      final popupFinder = find.byWidgetPredicate(
        (w) => w.runtimeType.toString().startsWith('PopupMenuButton'),
      );
      await tester.tap(popupFinder);
      await tester.pumpAndSettle();
      expect(find.text('Auto-scroll'), findsOneWidget);
      expect(find.text('Copy all to clipboard'), findsOneWidget);
    });
  });
}
