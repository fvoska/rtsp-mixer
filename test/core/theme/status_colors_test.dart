import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rtsp_mixer/core/theme/app_theme.dart';
import 'package:rtsp_mixer/core/theme/status_colors.dart';

/// WCAG relative-contrast ratio between two opaque colours.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  group('StatusColors registration', () {
    test('both themes resolve a non-null extension', () {
      expect(AppTheme.dark.extension<StatusColors>(), isNotNull);
      expect(AppTheme.light.extension<StatusColors>(), isNotNull);
    });

    test('live colour differs between light and dark', () {
      expect(
        AppTheme.light.extension<StatusColors>()!.live,
        isNot(AppTheme.dark.extension<StatusColors>()!.live),
      );
      expect(AppTheme.dark.extension<StatusColors>()!.live,
          const Color(0xFF3FBFAD));
      expect(AppTheme.light.extension<StatusColors>()!.live,
          const Color(0xFF0B8578));
    });

    test('reconnecting maps to the warning amber in both brightnesses', () {
      for (final s in [StatusColors.light, StatusColors.dark]) {
        expect(s.reconnecting, s.warning);
      }
    });
  });

  group('StatusColors contrast', () {
    // The actual defect being fixed: the old fixed dark-mode green (0xFF81C784)
    // measured ~1.7:1 on a white card — effectively invisible in light mode.
    test('light live colour clears 3:1 against a white surface', () {
      final live = AppTheme.light.extension<StatusColors>()!.live;
      expect(_contrast(live, const Color(0xFFFFFFFF)), greaterThan(3.0));
    });

    test('the old fixed green would NOT have cleared it', () {
      expect(
        _contrast(const Color(0xFF81C784), const Color(0xFFFFFFFF)),
        lessThan(3.0),
      );
    });

    test('every light status colour clears 3:1 on white', () {
      final s = AppTheme.light.extension<StatusColors>()!;
      for (final entry in {
        'live': s.live,
        'connecting': s.connecting,
        'reconnecting': s.reconnecting,
        'offline': s.offline,
        'warning': s.warning,
      }.entries) {
        expect(_contrast(entry.value, const Color(0xFFFFFFFF)),
            greaterThan(3.0),
            reason: '${entry.key} is too light for a white card');
      }
    });

    test('every dark status colour clears 3:1 on the dark card surface', () {
      final s = AppTheme.dark.extension<StatusColors>()!;
      final surface = AppTheme.dark.colorScheme.surface;
      for (final entry in {
        'live': s.live,
        'connecting': s.connecting,
        'reconnecting': s.reconnecting,
        'offline': s.offline,
        'warning': s.warning,
      }.entries) {
        expect(_contrast(entry.value, surface), greaterThan(3.0),
            reason: '${entry.key} is too dark for the petrol card');
      }
    });
  });

  group('StatusColors fallback (defensive)', () {
    // A widget test that builds a card under a bare ThemeData must not crash.
    testWidgets('bare ThemeData.light() yields the light instance',
        (tester) async {
      StatusColors? seen;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(),
          home: Builder(builder: (context) {
            seen = context.statusColors;
            return const SizedBox.shrink();
          }),
        ),
      );
      expect(seen, isNotNull);
      expect(seen, StatusColors.light);
      expect(tester.takeException(), isNull);
    });

    testWidgets('bare ThemeData.dark() yields the dark instance',
        (tester) async {
      StatusColors? seen;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Builder(builder: (context) {
            seen = context.statusColors;
            return const SizedBox.shrink();
          }),
        ),
      );
      expect(seen, StatusColors.dark);
      expect(tester.takeException(), isNull);
    });

    test('ThemeData accessor falls back by brightness without throwing', () {
      expect(ThemeData.light().statusColors, StatusColors.light);
      expect(ThemeData.dark().statusColors, StatusColors.dark);
    });

    test('registered extension wins over the fallback', () {
      expect(AppTheme.light.statusColors, StatusColors.light);
      expect(AppTheme.dark.statusColors, StatusColors.dark);
    });
  });

  group('StatusColors ThemeExtension contract', () {
    test('copyWith replaces only the named field', () {
      const red = Color(0xFFFF0000);
      final next = StatusColors.dark.copyWith(live: red);
      expect(next.live, red);
      expect(next.offline, StatusColors.dark.offline);
      expect(next.connecting, StatusColors.dark.connecting);
    });

    test('lerp at t=0 and t=1 returns the endpoints', () {
      final atZero = StatusColors.dark.lerp(StatusColors.light, 0.0);
      final atOne = StatusColors.dark.lerp(StatusColors.light, 1.0);
      expect(atZero.live, StatusColors.dark.live);
      expect(atOne.live, StatusColors.light.live);
    });

    test('lerp against a foreign extension returns this unchanged', () {
      expect(StatusColors.dark.lerp(null, 0.5), StatusColors.dark);
    });
  });
}
