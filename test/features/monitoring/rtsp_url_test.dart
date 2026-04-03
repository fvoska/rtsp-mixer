import 'package:flutter_test/flutter_test.dart';
import 'package:rtsp_audio_mixer/features/monitoring/helpers/rtsp_url.dart';

void main() {
  group('rtspUrl', () {
    test('constructs unencrypted RTSP URL with port 7447', () {
      expect(rtspUrl('192.168.1.1', 'abc123'), 'rtsp://192.168.1.1:7447/abc123');
    });

    test('strips trailing slash from host', () {
      expect(rtspUrl('192.168.1.1/', 'abc123'), 'rtsp://192.168.1.1:7447/abc123');
    });
  });

  group('rtspsUrl', () {
    test('constructs encrypted RTSPS URL with port 7441 and enableSrtp', () {
      expect(
        rtspsUrl('192.168.1.1', 'abc123'),
        'rtsps://192.168.1.1:7441/abc123?enableSrtp',
      );
    });

    test('strips trailing slash from host', () {
      expect(
        rtspsUrl('192.168.1.1/', 'abc123'),
        'rtsps://192.168.1.1:7441/abc123?enableSrtp',
      );
    });
  });
}
