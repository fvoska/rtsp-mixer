import 'package:flutter_test/flutter_test.dart';
import 'package:rtsp_mixer/features/monitoring/helpers/meter_urls.dart';

void main() {
  group('meterStreamUrls', () {
    const local = {
      'high': 'rtsps://10.0.0.5:7441/aliasHigh?enableSrtp',
      'medium': 'rtsps://10.0.0.5:7441/aliasMed?enableSrtp',
      'low': 'rtsps://10.0.0.5:7441/aliasLow?enableSrtp',
    };
    const remote = {
      'high': 'rtsps://nvr.ts.net:7441/aliasHigh?enableSrtp',
      'low': 'rtsps://nvr.ts.net:7441/aliasLow?enableSrtp',
    };

    test('prefers the low quality and rewrites Unifi URLs to plain RTSP', () {
      final urls = meterStreamUrls(
        local: local,
        remote: remote,
        cameraRemote: const {},
        isManual: false,
      );
      expect(urls, [
        'rtsp://10.0.0.5:7447/aliasLow',
        'rtsp://nvr.ts.net:7447/aliasLow',
      ]);
    });

    test('falls back through the quality preference list', () {
      final urls = meterStreamUrls(
        local: {'high': local['high']!, 'medium': local['medium']!},
        remote: const {},
        cameraRemote: const {},
        isManual: false,
      );
      expect(urls, ['rtsp://10.0.0.5:7447/aliasMed']);
    });

    test('uses any available quality when none of the preferred exist', () {
      final urls = meterStreamUrls(
        local: const {'package': 'rtsps://10.0.0.5:7441/aliasPkg?enableSrtp'},
        remote: const {},
        cameraRemote: const {},
        isManual: false,
      );
      expect(urls, ['rtsp://10.0.0.5:7447/aliasPkg']);
    });

    test('manual camera URLs pass through verbatim', () {
      final urls = meterStreamUrls(
        local: const {'low': 'rtsp://192.168.1.20:554/stream2'},
        remote: const {},
        cameraRemote: const {'low': 'rtsps://cam.example:8554/stream2'},
        isManual: true,
      );
      expect(urls, [
        'rtsp://192.168.1.20:554/stream2',
        'rtsps://cam.example:8554/stream2',
      ]);
    });

    test('duplicates are dropped after the rewrite', () {
      final urls = meterStreamUrls(
        local: const {'low': 'rtsps://10.0.0.5:7441/aliasLow?enableSrtp'},
        remote: const {'low': 'rtsp://10.0.0.5:7447/aliasLow'},
        cameraRemote: const {},
        isManual: false,
      );
      expect(urls, ['rtsp://10.0.0.5:7447/aliasLow']);
    });

    test('empty maps return an empty list (never throws)', () {
      expect(
        meterStreamUrls(
          local: const {},
          remote: const {},
          cameraRemote: const {},
          isManual: false,
        ),
        isEmpty,
      );
    });
  });
}
