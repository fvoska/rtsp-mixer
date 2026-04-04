import 'package:flutter_test/flutter_test.dart';
import 'package:rtsp_mixer/features/monitoring/helpers/pan_filter.dart';

void main() {
  group('buildPanFilter', () {
    test('center (0.0) produces balance 0.000', () {
      expect(
        buildPanFilter(0.0),
        'lavfi=[stereotools=balance_out=0.000]',
      );
    });

    test('full left (-1.0) produces balance -1.000', () {
      expect(
        buildPanFilter(-1.0),
        'lavfi=[stereotools=balance_out=-1.000]',
      );
    });

    test('full right (1.0) produces balance 1.000', () {
      expect(
        buildPanFilter(1.0),
        'lavfi=[stereotools=balance_out=1.000]',
      );
    });

    test('mostly left (-0.7) produces negative balance', () {
      final filter = buildPanFilter(-0.7);
      expect(filter, contains('balance_out=-0.700'));
    });

    test('clamps values above 1.0', () {
      expect(buildPanFilter(1.5), contains('balance_out=1.000'));
    });

    test('clamps values below -1.0', () {
      expect(buildPanFilter(-1.5), contains('balance_out=-1.000'));
    });
  });
}
