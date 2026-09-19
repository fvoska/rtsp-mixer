import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:rtsp_mixer/core/providers/settings_provider.dart';

void main() {
  group('AppSettings', () {
    test('default levelThreshold is 0.25', () {
      const s = AppSettings();
      expect(s.levelThreshold, kDefaultLevelThreshold);
      expect(s.levelThreshold, 0.25);
    });

    test('copyWith updates levelThreshold without touching other fields',
        () {
      const s = AppSettings(useRtsp: true, audioBufferSeconds: 0.3);
      final next = s.copyWith(levelThreshold: 0.2);
      expect(next.levelThreshold, 0.2);
      expect(next.useRtsp, true);
      expect(next.audioBufferSeconds, 0.3);
    });

    test('JSON round-trip preserves levelThreshold', () {
      const s = AppSettings(levelThreshold: 0.17);
      final round = AppSettings.fromJson(s.toJson());
      expect(round.levelThreshold, 0.17);
    });

    test('fromJson falls back to default when levelThreshold is missing',
        () {
      // Simulates settings files written before this field existed.
      final s = AppSettings.fromJson({
        'useRtsp': true,
        'audioBufferSeconds': 0.7,
      });
      expect(s.levelThreshold, 0.25);
      expect(s.useRtsp, true);
      expect(s.audioBufferSeconds, 0.7);
    });

    test('fromJson ignores the legacy variation-era activityThreshold key',
        () {
      // 0.05 was the old default for a peak-to-trough variation threshold;
      // on the noise-floor-relative level scale it would light the border
      // on every jitter. It must not be carried over.
      final s = AppSettings.fromJson({'activityThreshold': 0.05});
      expect(s.levelThreshold, kDefaultLevelThreshold);
    });

    test('toJson persists under levelThreshold, not activityThreshold', () {
      const s = AppSettings(levelThreshold: 0.3);
      final json = s.toJson();
      expect(json['levelThreshold'], 0.3);
      expect(json.containsKey('activityThreshold'), isFalse);
    });

    test('equality covers levelThreshold', () {
      const a = AppSettings(levelThreshold: 0.1);
      const b = AppSettings(levelThreshold: 0.1);
      const c = AppSettings(levelThreshold: 0.11);
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
        levelThreshold: 0.2,
      );
      final next = s.copyWith(themeMode: ThemeMode.dark);
      expect(next.themeMode, ThemeMode.dark);
      expect(next.useRtsp, true);
      expect(next.audioBufferSeconds, 0.3);
      expect(next.levelThreshold, 0.2);
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

  group('AppSettings.oledDark', () {
    test('defaults to off', () {
      expect(const AppSettings().oledDark, isFalse);
    });

    test('copyWith updates oledDark without touching other fields', () {
      const s = AppSettings(
        useRtsp: true,
        audioBufferSeconds: 0.3,
        levelThreshold: 0.2,
        themeMode: ThemeMode.dark,
      );
      final next = s.copyWith(oledDark: true);
      expect(next.oledDark, isTrue);
      expect(next.useRtsp, true);
      expect(next.audioBufferSeconds, 0.3);
      expect(next.levelThreshold, 0.2);
      expect(next.themeMode, ThemeMode.dark);
    });

    test('copyWith without oledDark preserves it', () {
      const s = AppSettings(oledDark: true);
      expect(s.copyWith(useRtsp: true).oledDark, isTrue);
    });

    test('survives being set under every theme mode', () {
      // The preference is orthogonal to how dark mode is reached: it must
      // persist under System (OS-resolved dark) and under an explicit Light
      // choice, not just under an explicit Dark one.
      for (final mode in ThemeMode.values) {
        final round = AppSettings.fromJson(
          AppSettings(themeMode: mode, oledDark: true).toJson(),
        );
        expect(round.oledDark, isTrue, reason: 'lost oledDark under $mode');
        expect(round.themeMode, mode);
      }
    });

    test('equality and hashCode cover oledDark', () {
      const a = AppSettings(oledDark: true);
      const b = AppSettings(oledDark: true);
      const c = AppSettings(oledDark: false);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
      expect(a.hashCode, isNot(c.hashCode));
    });

    group('malformed persisted payloads degrade to off', () {
      test('absent key (settings written before the field existed)', () {
        final s = AppSettings.fromJson({'themeMode': 'dark'});
        expect(s.oledDark, isFalse);
        expect(s.themeMode, ThemeMode.dark);
      });

      test('explicit null', () {
        expect(AppSettings.fromJson({'oledDark': null}).oledDark, isFalse);
      });

      test('wrong type', () {
        expect(AppSettings.fromJson({'oledDark': 'yes'}).oledDark, isFalse);
      });
    });
  });

  group('AppSettings.batterySaverMode', () {
    test('defaults to off', () {
      expect(const AppSettings().batterySaverMode, isFalse);
    });

    test('copyWith updates batterySaverMode without touching other fields', () {
      const s = AppSettings(
        useRtsp: true,
        audioBufferSeconds: 0.3,
        levelThreshold: 0.2,
        themeMode: ThemeMode.dark,
      );
      final next = s.copyWith(batterySaverMode: true);
      expect(next.batterySaverMode, isTrue);
      expect(next.useRtsp, true);
      expect(next.audioBufferSeconds, 0.3);
      expect(next.levelThreshold, 0.2);
      expect(next.themeMode, ThemeMode.dark);
    });

    test('copyWith without batterySaverMode preserves it', () {
      const s = AppSettings(batterySaverMode: true);
      expect(s.copyWith(useRtsp: true).batterySaverMode, isTrue);
    });

    test('round-trips through toJson/fromJson', () {
      final round = AppSettings.fromJson(
        const AppSettings(batterySaverMode: true).toJson(),
      );
      expect(round.batterySaverMode, isTrue);
    });

    test('equality and hashCode cover batterySaverMode', () {
      const a = AppSettings(batterySaverMode: true);
      const b = AppSettings(batterySaverMode: true);
      const c = AppSettings(batterySaverMode: false);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
      expect(a.hashCode, isNot(c.hashCode));
    });

    group('malformed persisted payloads degrade to off', () {
      test('absent key (settings written before the field existed)', () {
        final s = AppSettings.fromJson({'themeMode': 'dark'});
        expect(s.batterySaverMode, isFalse);
        expect(s.themeMode, ThemeMode.dark);
      });

      test('explicit null', () {
        expect(
          AppSettings.fromJson({'batterySaverMode': null}).batterySaverMode,
          isFalse,
        );
      });

      test('wrong type', () {
        expect(
          AppSettings.fromJson({'batterySaverMode': 'yes'}).batterySaverMode,
          isFalse,
        );
      });
    });
  });
}
