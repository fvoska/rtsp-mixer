import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:rtsp_mixer/core/providers/settings_provider.dart';

void main() {
  group('AppSettings', () {
    test('default activityThreshold is 0.05', () {
      const s = AppSettings();
      expect(s.activityThreshold, 0.05);
    });

    test('copyWith updates activityThreshold without touching other fields',
        () {
      const s = AppSettings(useRtsp: true, audioBufferSeconds: 0.3);
      final next = s.copyWith(activityThreshold: 0.2);
      expect(next.activityThreshold, 0.2);
      expect(next.useRtsp, true);
      expect(next.audioBufferSeconds, 0.3);
    });

    test('JSON round-trip preserves activityThreshold', () {
      const s = AppSettings(activityThreshold: 0.17);
      final round = AppSettings.fromJson(s.toJson());
      expect(round.activityThreshold, 0.17);
    });

    test('fromJson falls back to default when activityThreshold is missing',
        () {
      // Simulates settings files written before this field existed.
      final s = AppSettings.fromJson({
        'useRtsp': true,
        'audioBufferSeconds': 0.7,
      });
      expect(s.activityThreshold, 0.05);
      expect(s.useRtsp, true);
      expect(s.audioBufferSeconds, 0.7);
    });

    test('equality covers activityThreshold', () {
      const a = AppSettings(activityThreshold: 0.1);
      const b = AppSettings(activityThreshold: 0.1);
      const c = AppSettings(activityThreshold: 0.11);
      expect(a, b);
      expect(a, isNot(c));
    });

    test('toJson does not emit debugMode (removed)', () {
      const s = AppSettings();
      expect(s.toJson().containsKey('debugMode'), isFalse);
    });
  });

  group('AppSettings.themeMode', () {
    test('defaults to system', () {
      expect(const AppSettings().themeMode, ThemeMode.system);
    });

    test('copyWith updates themeMode without touching other fields', () {
      const s = AppSettings(
        useRtsp: true,
        audioBufferSeconds: 0.3,
        activityThreshold: 0.2,
      );
      final next = s.copyWith(themeMode: ThemeMode.dark);
      expect(next.themeMode, ThemeMode.dark);
      expect(next.useRtsp, true);
      expect(next.audioBufferSeconds, 0.3);
      expect(next.activityThreshold, 0.2);
    });

    test('copyWith without themeMode preserves the current mode', () {
      const s = AppSettings(themeMode: ThemeMode.light);
      expect(s.copyWith(useRtsp: true).themeMode, ThemeMode.light);
    });

    test('JSON round-trip preserves every mode', () {
      for (final mode in ThemeMode.values) {
        final round = AppSettings.fromJson(AppSettings(themeMode: mode).toJson());
        expect(round.themeMode, mode, reason: 'round-trip failed for $mode');
      }
    });

    test('persisted as a stable name, not an enum index', () {
      // An index would silently flip a user's theme if the SDK ever reorders
      // ThemeMode. Pin the wire format.
      expect(const AppSettings(themeMode: ThemeMode.dark).toJson()['themeMode'],
          'dark');
      expect(const AppSettings(themeMode: ThemeMode.light).toJson()['themeMode'],
          'light');
      expect(
          const AppSettings(themeMode: ThemeMode.system).toJson()['themeMode'],
          'system');
    });

    test('equality and hashCode cover themeMode', () {
      const a = AppSettings(themeMode: ThemeMode.dark);
      const b = AppSettings(themeMode: ThemeMode.dark);
      const c = AppSettings(themeMode: ThemeMode.light);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
      expect(a.hashCode, isNot(c.hashCode));
    });

    group('malformed persisted payloads degrade to system', () {
      test('absent key (settings written before the field existed)', () {
        final s = AppSettings.fromJson({'useRtsp': true});
        expect(s.themeMode, ThemeMode.system);
        expect(s.useRtsp, true);
      });

      test('explicit null', () {
        expect(AppSettings.fromJson({'themeMode': null}).themeMode,
            ThemeMode.system);
      });

      test('unrecognised string', () {
        expect(AppSettings.fromJson({'themeMode': 'sepia'}).themeMode,
            ThemeMode.system);
      });

      test('wrong type (a raw enum index from a hypothetical old build)', () {
        expect(
            AppSettings.fromJson({'themeMode': 2}).themeMode, ThemeMode.system);
      });
    });
  });
}
