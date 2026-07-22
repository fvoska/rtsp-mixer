import 'package:flutter_test/flutter_test.dart';
import 'package:rtsp_mixer/features/monitoring/helpers/rtsp_url.dart';

void main() {
  group('replaceUrlHost', () {
    test('swaps only the host — preserves scheme, port, path, and query', () {
      expect(
        replaceUrlHost('rtsps://10.0.0.5:7441/abc?enableSrtp', '100.64.0.9'),
        'rtsps://100.64.0.9:7441/abc?enableSrtp',
      );
    });

    test('preserves plain RTSP scheme and port 7447', () {
      expect(
        replaceUrlHost('rtsp://10.0.0.5:7447/abc', '100.64.0.9'),
        'rtsp://100.64.0.9:7447/abc',
      );
    });

    test('tolerates newHost pasted with a scheme prefix', () {
      expect(
        replaceUrlHost('rtsps://10.0.0.5:7441/abc?enableSrtp', 'https://100.64.0.9'),
        'rtsps://100.64.0.9:7441/abc?enableSrtp',
      );
      expect(
        replaceUrlHost('rtsp://10.0.0.5:7447/abc', 'rtsp://100.64.0.9'),
        'rtsp://100.64.0.9:7447/abc',
      );
    });

    test('tolerates newHost with trailing slash', () {
      expect(
        replaceUrlHost('rtsps://10.0.0.5:7441/abc?enableSrtp', '100.64.0.9/'),
        'rtsps://100.64.0.9:7441/abc?enableSrtp',
      );
    });

    test('tolerates newHost with scheme prefix AND trailing slash', () {
      expect(
        replaceUrlHost('rtsps://10.0.0.5:7441/abc?enableSrtp', 'https://100.64.0.9/'),
        'rtsps://100.64.0.9:7441/abc?enableSrtp',
      );
    });

    test('trims whitespace around newHost', () {
      expect(
        replaceUrlHost('rtsp://10.0.0.5:7447/abc', '  100.64.0.9  '),
        'rtsp://100.64.0.9:7447/abc',
      );
    });

    test('returns the original URL unchanged when URL parsing fails', () {
      expect(replaceUrlHost('not a url at all %%%', '100.64.0.9'),
          'not a url at all %%%');
      expect(replaceUrlHost('', '100.64.0.9'), '');
    });

    test('returns the original URL unchanged when newHost is empty', () {
      expect(
        replaceUrlHost('rtsp://10.0.0.5:7447/abc', ''),
        'rtsp://10.0.0.5:7447/abc',
      );
      expect(
        replaceUrlHost('rtsp://10.0.0.5:7447/abc', '   '),
        'rtsp://10.0.0.5:7447/abc',
      );
    });

    test('never throws on garbage input', () {
      expect(() => replaceUrlHost('::::', ':::'), returnsNormally);
    });

    test('works with hostname (Tailscale MagicDNS) as newHost', () {
      expect(
        replaceUrlHost('rtsps://10.0.0.5:7441/abc?enableSrtp', 'nvr.tailnet.ts.net'),
        'rtsps://nvr.tailnet.ts.net:7441/abc?enableSrtp',
      );
    });
  });
}
