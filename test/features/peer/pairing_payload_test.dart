import 'package:flutter_test/flutter_test.dart';
import 'package:rtsp_mixer/features/peer/models/pairing_payload.dart';
import 'package:rtsp_mixer/features/peer/peer_protocol.dart';

void main() {
  const payload = PairingPayload(
    hostId: 'abc123',
    hostName: 'Nursery phone',
    address: '192.168.1.20',
    port: 47831,
    code: '123456',
  );

  test('round-trips through the roomtone://pair URI', () {
    final raw = payload.toString();
    expect(raw, startsWith('roomtone://pair?'));
    final parsed = PairingPayload.tryParse(raw);
    expect(parsed, isNotNull);
    expect(parsed!.hostId, 'abc123');
    expect(parsed.hostName, 'Nursery phone');
    expect(parsed.address, '192.168.1.20');
    expect(parsed.port, 47831);
    expect(parsed.code, '123456');
    expect(parsed.protocol, kPeerProtocolVersion);
    expect(parsed.isSupportedProtocol, isTrue);
  });

  test('rejects foreign QR content without throwing', () {
    expect(PairingPayload.tryParse(null), isNull);
    expect(PairingPayload.tryParse(''), isNull);
    expect(PairingPayload.tryParse('WIFI:S:home;T:WPA;P:pw;;'), isNull);
    expect(PairingPayload.tryParse('https://example.com/pair?c=1'), isNull);
    expect(PairingPayload.tryParse('roomtone://other?id=a&h=b&p=1&c=2'), isNull);
    expect(PairingPayload.tryParse('roomtone://pair?id=a&h=b&p=99999&c=2'),
        isNull);
    expect(PairingPayload.tryParse('roomtone://pair?id=a&h=b&p=1'), isNull);
  });

  test('missing name falls back and unknown version is flagged', () {
    final parsed = PairingPayload.tryParse(
        'roomtone://pair?v=9&id=a&h=10.0.0.5&p=1234&c=000111');
    expect(parsed, isNotNull);
    expect(parsed!.hostName, 'Phone camera');
    expect(parsed.isSupportedProtocol, isFalse);
  });
}
