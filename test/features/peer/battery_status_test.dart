import 'package:flutter_test/flutter_test.dart';
import 'package:rtsp_mixer/features/peer/models/battery_status.dart';

void main() {
  group('BatteryStatus', () {
    test('round-trips through JSON', () {
      const b = BatteryStatus(percent: 73, plugged: true);
      expect(b.toJson(), {'percent': 73, 'plugged': true});
      expect(BatteryStatus.tryFromJson(b.toJson()), b);
    });

    test('tolerates missing, garbage and out-of-range wire values', () {
      expect(BatteryStatus.tryFromJson(null), isNull);
      expect(BatteryStatus.tryFromJson('73%'), isNull);
      expect(BatteryStatus.tryFromJson({'plugged': true}), isNull);
      expect(BatteryStatus.tryFromJson({'percent': 'full'}), isNull);
      expect(BatteryStatus.tryFromJson({'percent': double.nan}), isNull);
      expect(BatteryStatus.tryFromJson({'percent': 250}),
          const BatteryStatus(percent: 100, plugged: false));
      expect(BatteryStatus.tryFromJson({'percent': -3, 'plugged': 'yes'}),
          const BatteryStatus(percent: 0, plugged: false));
      expect(BatteryStatus.tryFromJson({'percent': 49.6, 'plugged': true}),
          const BatteryStatus(percent: 50, plugged: true));
    });

    test('low and critical only while unplugged', () {
      expect(const BatteryStatus(percent: 20, plugged: false).isLow, isTrue);
      expect(const BatteryStatus(percent: 21, plugged: false).isLow, isFalse);
      expect(const BatteryStatus(percent: 10, plugged: false).isCritical, isTrue);
      expect(const BatteryStatus(percent: 11, plugged: false).isCritical, isFalse);
      expect(const BatteryStatus(percent: 5, plugged: true).isLow, isFalse);
      expect(const BatteryStatus(percent: 5, plugged: true).isCritical, isFalse);
    });

    test('label reads as a sentence fragment', () {
      expect(const BatteryStatus(percent: 73, plugged: true).label,
          '73% · charging');
      expect(const BatteryStatus(percent: 12, plugged: false).label,
          '12% · on battery');
    });
  });
}
