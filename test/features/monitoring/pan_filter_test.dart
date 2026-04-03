import 'package:flutter_test/flutter_test.dart';
import 'package:rtsp_audio_mixer/features/monitoring/helpers/pan_filter.dart';

void main() {
  group('buildPanFilter', () {
    test('center (0.0) produces equal left and right gain', () {
      expect(
        buildPanFilter(0.0),
        'lavfi=[pan=stereo|FL=0.500*c0|FR=0.500*c0]',
      );
    });

    test('full left (-1.0) sends all audio to left channel', () {
      expect(
        buildPanFilter(-1.0),
        'lavfi=[pan=stereo|FL=1.000*c0|FR=0.000*c0]',
      );
    });

    test('full right (1.0) sends all audio to right channel', () {
      expect(
        buildPanFilter(1.0),
        'lavfi=[pan=stereo|FL=0.000*c0|FR=1.000*c0]',
      );
    });

    test('mostly left (-0.7) produces leftGain > rightGain', () {
      final filter = buildPanFilter(-0.7);
      // leftGain = (1 - (-0.7)) / 2 = 0.85
      // rightGain = (1 + (-0.7)) / 2 = 0.15
      expect(filter, contains('FL=0.850*c0'));
      expect(filter, contains('FR=0.150*c0'));
    });

    test('clamps values above 1.0 to full right', () {
      expect(
        buildPanFilter(1.5),
        'lavfi=[pan=stereo|FL=0.000*c0|FR=1.000*c0]',
      );
    });

    test('clamps values below -1.0 to full left', () {
      expect(
        buildPanFilter(-1.5),
        'lavfi=[pan=stereo|FL=1.000*c0|FR=0.000*c0]',
      );
    });
  });
}
