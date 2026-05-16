import 'package:flutter_test/flutter_test.dart';
import 'package:rtsp_mixer/features/monitoring/models/health_event.dart';

void main() {
  group('HealthEventType.driftResync', () {
    test('appears in the enum', () {
      expect(HealthEventType.values, contains(HealthEventType.driftResync));
    });

    test('serializes to "driftResync"', () {
      final e = HealthEvent(
        timestamp: DateTime.fromMillisecondsSinceEpoch(1234),
        type: HealthEventType.driftResync,
        cameraId: 'cam1',
        cameraName: 'Nursery',
        detail: 'cache=2.50s > 1.50s',
      );
      expect(e.toJson()['type'], 'driftResync');
    });

    test('JSON round-trip preserves all fields', () {
      final original = HealthEvent(
        timestamp: DateTime.fromMillisecondsSinceEpoch(1234),
        type: HealthEventType.driftResync,
        cameraId: 'cam1',
        cameraName: 'Nursery',
        detail: 'cache=2.50s > 1.50s',
      );
      final round = HealthEvent.fromJson(original.toJson());
      expect(round.type, HealthEventType.driftResync);
      expect(round.timestamp, original.timestamp);
      expect(round.cameraId, 'cam1');
      expect(round.cameraName, 'Nursery');
      expect(round.detail, 'cache=2.50s > 1.50s');
    });
  });
}
