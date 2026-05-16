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
}
