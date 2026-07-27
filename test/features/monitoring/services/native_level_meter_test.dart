import 'package:flutter_test/flutter_test.dart';
import 'package:rtsp_mixer/features/monitoring/services/native_level_meter.dart';

void main() {
  group('nativeLevelEventFromDynamic', () {
    test('parses a level event', () {
      final e = nativeLevelEventFromDynamic({
        'type': 'level',
        'cameraId': 'cam1',
        'rmsDb': -42.5,
        'peakDb': -30.1,
      });
      expect(e, isNotNull);
      expect(e!.isLevel, isTrue);
      expect(e.cameraId, 'cam1');
      expect(e.rmsDb, closeTo(-42.5, 1e-9));
      expect(e.peakDb, closeTo(-30.1, 1e-9));
    });

    test('parses integer dB values (platform channels may send ints)', () {
      final e = nativeLevelEventFromDynamic({
        'type': 'level',
        'cameraId': 'cam1',
        'rmsDb': -100,
      });
      expect(e, isNotNull);
      expect(e!.rmsDb, -100.0);
    });

    test('parses a status event with optional detail', () {
      final e = nativeLevelEventFromDynamic({
        'type': 'status',
        'cameraId': 'cam2',
        'state': 'retrying',
        'detail': 'pcm stall',
      });
      expect(e, isNotNull);
      expect(e!.isLevel, isFalse);
      expect(e.state, 'retrying');
      expect(e.detail, 'pcm stall');
    });

    test('rejects malformed events instead of throwing', () {
      expect(nativeLevelEventFromDynamic(null), isNull);
      expect(nativeLevelEventFromDynamic('nonsense'), isNull);
      expect(nativeLevelEventFromDynamic(<String, Object?>{}), isNull);
      expect(
        nativeLevelEventFromDynamic({'type': 'level', 'cameraId': ''}),
        isNull,
      );
      expect(
        nativeLevelEventFromDynamic({'type': 'level', 'cameraId': 'cam1'}),
        isNull, // level event without rmsDb carries no signal
      );
      expect(
        nativeLevelEventFromDynamic(
            {'type': 'level', 'cameraId': 'cam1', 'rmsDb': 'loud'}),
        isNull,
      );
      expect(
        nativeLevelEventFromDynamic(
            {'type': 'unknown', 'cameraId': 'cam1'}),
        isNull,
      );
    });

    test('rejects non-finite dB values', () {
      expect(
        nativeLevelEventFromDynamic({
          'type': 'level',
          'cameraId': 'cam1',
          'rmsDb': double.nan,
        }),
        isNull,
      );
      final e = nativeLevelEventFromDynamic({
        'type': 'level',
        'cameraId': 'cam1',
        'rmsDb': -40.0,
        'peakDb': double.infinity,
      });
      expect(e, isNotNull);
      expect(e!.peakDb, isNull); // bad peak dropped, good rms kept
    });
  });
}
