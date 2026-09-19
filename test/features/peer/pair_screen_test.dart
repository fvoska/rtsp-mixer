import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:rtsp_mixer/core/api/protect_api_client.dart';
import 'package:rtsp_mixer/core/storage/storage_service.dart';
import 'package:rtsp_mixer/features/auth/providers/auth_provider.dart';
import 'package:rtsp_mixer/features/cameras/providers/camera_provider.dart';
import 'package:rtsp_mixer/features/peer/models/discovered_host.dart';
import 'package:rtsp_mixer/features/peer/providers/peer_pairing_provider.dart';
import 'package:rtsp_mixer/features/peer/screens/pair_screen.dart';
import 'package:rtsp_mixer/features/peer/services/discovery.dart';
import 'package:rtsp_mixer/features/peer/services/peer_pairing_client.dart';

/// Scanner that "finds" one host without touching the network.
class _FakeScanner extends DiscoveryScanner {
  _FakeScanner(this.host);
  final DiscoveredHost host;
  final _controller = StreamController<List<DiscoveredHost>>.broadcast();

  @override
  Stream<List<DiscoveredHost>> get hosts => _controller.stream;

  @override
  List<DiscoveredHost> get currentHosts => [host];

  @override
  Future<bool> start() async {
    scheduleMicrotask(() => _controller.add([host]));
    return true;
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async => _controller.close();
}

class _FakeClient extends PeerPairingClient {
  final calls = <({String address, int port, String code})>[];
  @override
  Future<PairResult> pair({
    required String address,
    required int port,
    required String code,
    required String clientId,
    required String clientName,
  }) async {
    calls.add((address: address, port: port, code: code));
    if (code != '123456') {
      return const PairResult.failed(PairFailure.wrongCode,
          message: 'Wrong code — check the code on the host phone.');
    }
    return const PairResult.success(
        token: 'tok', hostId: 'host-1', hostName: 'Nursery phone');
  }
}

class _NoApi extends ProtectApiClient {}

/// The pairing screen shows an indeterminate spinner while scanning, so
/// pumpAndSettle would never settle — pump a few frames instead.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('discovered host → code dialog → paired camera added',
      (tester) async {
    final host = DiscoveredHost(
      hostId: 'host-1',
      name: 'Nursery phone',
      address: '192.168.1.20',
      port: 47831,
      protocol: 1,
      lastSeen: DateTime.now(),
    );
    final client = _FakeClient();
    final storage = StorageService.inMemory();
    final container = ProviderContainer(overrides: [
      storageProvider.overrideWithValue(storage),
      apiClientProvider.overrideWithValue(_NoApi()),
      peerPairingClientProvider.overrideWithValue(client),
      discoveryScannerFactoryProvider.overrideWithValue(() => _FakeScanner(host)),
    ]);
    addTearDown(container.dispose);

    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(body: Text('picker'))),
        GoRoute(path: '/pair', builder: (_, _) => const PairScreen()),
      ],
    );
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pump();
    // Pushed from the picker, exactly as the app does it.
    router.push('/pair');
    await _settle(tester);
    expect(find.text('Nursery phone'), findsOneWidget);
    expect(find.text('192.168.1.20:47831'), findsOneWidget);

    await tester.tap(find.text('Nursery phone'));
    await _settle(tester);
    expect(find.text('Pair with Nursery phone'), findsOneWidget);

    // Wrong code surfaces the host's error copy, keeps the screen.
    await tester.enterText(find.byType(TextFormField), '000 000');
    await tester.tap(find.text('Pair'));
    await _settle(tester);
    expect(find.textContaining('Wrong code'), findsOneWidget);
    expect(client.calls.single.code, '000000');

    // Right code pairs, adds the peer camera, pops back.
    await tester.tap(find.text('Nursery phone'));
    await _settle(tester);
    await tester.enterText(find.byType(TextFormField), '123 456');
    await tester.tap(find.text('Pair'));
    await _settle(tester);
    expect(client.calls.last.address, '192.168.1.20');
    expect(client.calls.last.port, 47831);
    final cams = container.read(cameraNotifierProvider).value?.cameras ?? [];
    expect(cams, hasLength(1));
    expect(cams.single.isPeer, isTrue);
    expect(cams.single.peerHostId, 'host-1');
    expect(cams.single.defaultStreamUrl,
        'http://192.168.1.20:47831/roomtone/v1/audio.wav?token=tok');
    // Let the page-pop transition finish.
    await tester.pump(const Duration(seconds: 1));
    await _settle(tester);
    expect(find.byType(PairScreen), findsNothing);
    expect(find.text('picker'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
