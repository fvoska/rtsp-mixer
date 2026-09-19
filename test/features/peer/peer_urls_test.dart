import 'package:flutter_test/flutter_test.dart';
import 'package:rtsp_mixer/features/peer/helpers/peer_urls.dart';

void main() {
  test('stream and status URLs carry the token and paths', () {
    final s = peerStreamUrl('192.168.1.20', 47831, 'tok');
    expect(s, 'http://192.168.1.20:47831/roomtone/v1/audio.wav?token=tok');
    expect(peerStatusUrl('192.168.1.20', 47831, 'tok'),
        'http://192.168.1.20:47831/roomtone/v1/status?token=tok');
    expect(peerInfoUrl('192.168.1.20', 47831),
        'http://192.168.1.20:47831/roomtone/v1/info');
    expect(isPeerStreamUrl(s), isTrue);
    expect(isPeerStreamUrl('rtsp://x/y'), isFalse);
    expect(isPeerStreamUrl(null), isFalse);
  });

  test('status URL is derived from a stream URL', () {
    final s = peerStreamUrl('10.0.0.2', 5000, 'abc');
    expect(peerStatusUrlFromStream(s),
        'http://10.0.0.2:5000/roomtone/v1/status?token=abc');
    expect(peerStatusUrlFromStream('rtsp://cam/live'), isNull);
    expect(peerStatusUrlFromStream(null), isNull);
  });

  test('repoint keeps token and path while swapping address', () {
    final s = peerStreamUrl('10.0.0.2', 5000, 'abc');
    expect(repointPeerUrl(s, '10.0.0.9', 47831),
        'http://10.0.0.9:47831/roomtone/v1/audio.wav?token=abc');
    expect(repointPeerUrl('::not a url::', '1.2.3.4', 1), '::not a url::');
  });

  test('address label hides the token', () {
    expect(peerAddressLabel(peerStreamUrl('10.0.0.2', 5000, 'secret')),
        '10.0.0.2:5000');
    expect(peerAddressLabel(null), '');
  });

  test('IPv6 literals are bracketed', () {
    expect(peerInfoUrl('fe80::1', 8080),
        'http://[fe80::1]:8080/roomtone/v1/info');
  });
}
