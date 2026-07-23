import 'package:flutter_test/flutter_test.dart';
import 'package:rtsp_mixer/features/monitoring/helpers/stream_candidates.dart';

void main() {
  group('orderedStreamCandidates', () {
    test('orders local, remote, override for a Unifi-style quality map', () {
      final candidates = orderedStreamCandidates(
        local: {'low': 'rtsp://192.168.1.1:7447/abc'},
        remote: {'low': 'rtsp://nvr.tailnet.ts.net:7447/abc'},
        cameraRemote: const {},
        quality: 'low',
      );
      expect(candidates, [
        (label: 'local', url: 'rtsp://192.168.1.1:7447/abc'),
        (label: 'remote', url: 'rtsp://nvr.tailnet.ts.net:7447/abc'),
      ]);
    });

    test('manual camera gets all three tiers in order', () {
      final candidates = orderedStreamCandidates(
        local: {'stream': 'rtsp://192.168.1.50:554/live'},
        remote: {'stream': 'rtsp://home.tailnet.ts.net:554/live'},
        cameraRemote: {'stream': 'rtsp://cam1.tailnet.ts.net:8554/other'},
        quality: 'stream',
      );
      expect(candidates, [
        (label: 'local', url: 'rtsp://192.168.1.50:554/live'),
        (label: 'remote', url: 'rtsp://home.tailnet.ts.net:554/live'),
        (label: 'override', url: 'rtsp://cam1.tailnet.ts.net:8554/other'),
      ]);
    });

    test('drops duplicates of an earlier candidate', () {
      final candidates = orderedStreamCandidates(
        local: {'stream': 'rtsp://10.0.0.5:554/live'},
        remote: {'stream': 'rtsp://10.0.0.5:554/live'},
        cameraRemote: {'stream': 'rtsp://10.0.0.5:554/live'},
        quality: 'stream',
      );
      expect(candidates, [
        (label: 'local', url: 'rtsp://10.0.0.5:554/live'),
      ]);
    });

    test('skips empty and missing tiers', () {
      final candidates = orderedStreamCandidates(
        local: const {},
        remote: {'low': ''},
        cameraRemote: {'low': 'rtsp://cam.tailnet.ts.net:554/live'},
        quality: 'low',
      );
      expect(candidates, [
        (label: 'override', url: 'rtsp://cam.tailnet.ts.net:554/live'),
      ]);
    });

    test('falls back to activeUrl when the maps yield nothing', () {
      final candidates = orderedStreamCandidates(
        local: const {},
        remote: const {},
        cameraRemote: const {},
        quality: 'low',
        activeUrl: 'rtsp://10.0.0.5:7447/abc',
      );
      expect(candidates, [
        (label: 'active', url: 'rtsp://10.0.0.5:7447/abc'),
      ]);
    });

    test('returns empty when quality is null and no activeUrl', () {
      final candidates = orderedStreamCandidates(
        local: {'low': 'rtsp://10.0.0.5:7447/abc'},
        remote: const {},
        cameraRemote: const {},
        quality: null,
      );
      expect(candidates, isEmpty);
    });

    test('never throws', () {
      expect(
        () => orderedStreamCandidates(
          local: const {},
          remote: const {},
          cameraRemote: const {},
          quality: null,
          activeUrl: '',
        ),
        returnsNormally,
      );
    });
  });
}
