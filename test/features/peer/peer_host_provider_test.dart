import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rtsp_mixer/core/storage/storage_service.dart';
import 'package:rtsp_mixer/features/auth/providers/auth_provider.dart';
import 'package:rtsp_mixer/features/peer/models/peer_host_state.dart';
import 'package:rtsp_mixer/features/peer/providers/peer_host_provider.dart';
import 'package:rtsp_mixer/features/peer/services/mic_capture.dart';
import 'package:rtsp_mixer/features/peer/services/peer_pairing_client.dart';

import '../../support/async.dart';

class _FakeMic implements AudioCaptureSource {
  _FakeMic({this.permitted = true});
  final bool permitted;
  StreamController<Uint8List>? controller;
  int starts = 0;
  int stops = 0;

  @override
  Future<bool> hasPermission({bool request = true}) async => permitted;

  @override
  Future<Stream<Uint8List>> start() async {
    starts++;
    controller = StreamController<Uint8List>();
    return controller!.stream;
  }

  @override
  Future<void> stop() async {
    stops++;
    await controller?.close();
  }

  @override
  Future<void> dispose() async {}
}

ProviderContainer _container(StorageService storage, _FakeMic mic) =>
    ProviderContainer(overrides: [
      storageProvider.overrideWithValue(storage),
      audioCaptureSourceProvider.overrideWithValue(mic),
      peerHostOptionsProvider.overrideWithValue(PeerHostOptions(
        bindAddress: InternetAddress.loopbackIPv4,
        httpPort: 0,
        discoveryPort: 0,
        useForegroundService: false,
      )),
    ]);

Future<PeerHostState> _waitRunning(ProviderContainer c) async {
  await waitFor(() => c.read(peerHostProvider).isRunning,
      reason: 'host mode reaches running');
  return c.read(peerHostProvider);
}

void main() {
  late StorageService storage;
  late _FakeMic mic;

  setUp(() {
    storage = StorageService();
    mic = _FakeMic();
  });

  test('start serves on loopback with a fresh code and persists auto-resume',
      () async {
    final c = _container(storage, mic);
    addTearDown(c.dispose);
    await c.read(peerHostProvider.notifier).start();
    final s = await _waitRunning(c);
    expect(s.code, matches(RegExp(r'^\d{6}$')));
    expect(s.port, isNotNull);
    expect(s.addresses, ['127.0.0.1']);
    expect(s.discoveryActive, isTrue);
    expect(s.autoResume, isTrue);
    expect(mic.starts, 1);
    final saved = await storage.loadPeerHostConfig();
    expect(saved!['autoResume'], true);
    expect(saved['hostId'], s.hostId);
    await c.read(peerHostProvider.notifier).stop();
    expect(c.read(peerHostProvider).status, PeerHostStatus.idle);
    expect((await storage.loadPeerHostConfig())!['autoResume'], false);
  });

  test('pairing issues a token, rotates the code, and revoke kills the token',
      () async {
    final c = _container(storage, mic);
    addTearDown(c.dispose);
    await c.read(peerHostProvider.notifier).start();
    final s = await _waitRunning(c);
    final client = PeerPairingClient();

    final wrong = await client.pair(
        address: '127.0.0.1',
        port: s.port!,
        code: '000000',
        clientId: 'mon-1',
        clientName: 'Pixel');
    expect(wrong.failure, PairFailure.wrongCode);
    await waitFor(
        () => c.read(peerHostProvider).lastPairingNote?.contains('Wrong') == true,
        reason: 'host notes the wrong code');

    final ok = await client.pair(
        address: '127.0.0.1',
        port: s.port!,
        code: s.code,
        clientId: 'mon-1',
        clientName: 'Pixel');
    expect(ok.isSuccess, isTrue);
    final after = c.read(peerHostProvider);
    expect(after.pairedClients.single.name, 'Pixel');
    expect(after.code, isNot(s.code));
    expect((await storage.loadPeerHostConfig())!['paired'], hasLength(1));

    // Token works for status…
    final http = HttpClient();
    Future<int> status() async {
      final req = await http.getUrl(Uri.parse(
          'http://127.0.0.1:${s.port}/roomtone/v1/status?token=${ok.token}'));
      final res = await req.close();
      await res.drain<void>();
      return res.statusCode;
    }
    expect(await status(), 200);
    // …until revoked.
    await c.read(peerHostProvider.notifier).revoke('mon-1');
    expect(await status(), 401);
    http.close(force: true);
    await c.read(peerHostProvider.notifier).stop();
  });

  test('mic chunks raise the level; a dead mic stream is restarted', () async {
    final c = _container(storage, mic);
    addTearDown(c.dispose);
    await c.read(peerHostProvider.notifier).start();
    await _waitRunning(c);
    final loud = Uint8List(3200);
    for (var i = 0; i < loud.length; i += 2) {
      loud[i] = 0x00;
      loud[i + 1] = 0x40; // 0x4000 = half scale
    }
    mic.controller!.add(loud);
    await waitFor(() => c.read(peerHostProvider).level > 0.5,
        reason: 'level meter reflects a loud chunk');
    // Kill the stream: the notifier schedules a restart (1s backoff).
    await mic.controller!.close();
    await waitFor(() => mic.starts == 2,
        reason: 'microphone capture restarted after the stream ended',
        timeout: const Duration(seconds: 5));
    await c.read(peerHostProvider.notifier).stop();
  });

  test('denied microphone permission yields an error state, not a throw',
      () async {
    final c = _container(storage, _FakeMic(permitted: false));
    addTearDown(c.dispose);
    await c.read(peerHostProvider.notifier).start();
    final s = c.read(peerHostProvider);
    expect(s.status, PeerHostStatus.error);
    expect(s.errorMessage, contains('Microphone permission'));
    expect(s.autoResume, isFalse);
  });

  test('auto-resume starts hosting on build when the flag was saved', () async {
    await storage.savePeerHostConfig({
      'hostId': 'persisted-host',
      'name': 'Nursery phone',
      'paired': [],
      'autoResume': true,
    });
    final c = _container(storage, mic);
    addTearDown(c.dispose);
    final s = await _waitRunning(c);
    expect(s.hostId, 'persisted-host');
    expect(s.name, 'Nursery phone');
    await c.read(peerHostProvider.notifier).stop();
  });

  test('setName applies live to /info', () async {
    final c = _container(storage, mic);
    addTearDown(c.dispose);
    await c.read(peerHostProvider.notifier).start();
    final s = await _waitRunning(c);
    await c.read(peerHostProvider.notifier).setName('Kitchen');
    final info = await PeerPairingClient().fetchInfo('127.0.0.1', s.port!);
    expect(info!.name, 'Kitchen');
    await c.read(peerHostProvider.notifier).stop();
  });
}
