import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rtsp_mixer/features/peer/services/pairing_code.dart';
import 'package:rtsp_mixer/features/peer/services/peer_host_server.dart';
import 'package:rtsp_mixer/features/peer/services/peer_pairing_client.dart';

void main() {
  late PeerHostServer server;
  late int port;
  final audio = StreamController<Uint8List>.broadcast();

  setUp(() async {
    server = PeerHostServer(
      hostId: 'h1',
      hostName: () => 'Kitchen phone',
      pairingCode: () => '424242',
      isTokenValid: (_) => true,
      issueToken: (_, _) async => 'secret-token',
      audio: audio.stream,
      currentLevel: () => 0,
      gate: PairingGate(maxFailures: 100),
    );
    port = await server.start(
        bindAddress: InternetAddress.loopbackIPv4, preferredPort: 0);
  });

  tearDown(() => server.stop());

  test('fetchInfo identifies a Roomtone host', () async {
    final info = await PeerPairingClient().fetchInfo('127.0.0.1', port);
    expect(info, isNotNull);
    expect(info!.hostId, 'h1');
    expect(info.name, 'Kitchen phone');
    expect(info.port, port);
  });

  test('pair succeeds with the right code', () async {
    final r = await PeerPairingClient().pair(
      address: '127.0.0.1',
      port: port,
      code: '424 242',
      clientId: 'c1',
      clientName: 'Pixel',
    );
    expect(r.isSuccess, isTrue);
    expect(r.token, 'secret-token');
    expect(r.hostId, 'h1');
    expect(r.hostName, 'Kitchen phone');
  });

  test('pair reports a wrong code', () async {
    final r = await PeerPairingClient().pair(
      address: '127.0.0.1',
      port: port,
      code: '000000',
      clientId: 'c1',
      clientName: 'Pixel',
    );
    expect(r.isSuccess, isFalse);
    expect(r.failure, PairFailure.wrongCode);
  });

  test('unreachable host is reported, not thrown', () async {
    // Bind then close a socket to get a port nothing listens on.
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final deadPort = probe.port;
    await probe.close();
    final client = PeerPairingClient(timeout: const Duration(seconds: 2));
    final r = await client.pair(
      address: '127.0.0.1',
      port: deadPort,
      code: '424242',
      clientId: 'c1',
      clientName: 'Pixel',
    );
    expect(r.isSuccess, isFalse);
    expect(r.failure, PairFailure.unreachable);
    expect(await client.fetchInfo('127.0.0.1', deadPort), isNull);
  });
}
