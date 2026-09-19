import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:rtsp_mixer/core/storage/storage_service.dart';
import 'package:rtsp_mixer/core/theme/app_theme.dart';
import 'package:rtsp_mixer/features/auth/providers/auth_provider.dart';
import 'package:rtsp_mixer/features/peer/providers/peer_host_provider.dart';
import 'package:rtsp_mixer/features/peer/screens/host_screen.dart';
import 'package:rtsp_mixer/features/peer/services/mic_capture.dart';

class _FakeMic implements AudioCaptureSource {
  StreamController<Uint8List>? controller;
  @override
  Future<bool> hasPermission({bool request = true}) async => true;
  @override
  Future<Stream<Uint8List>> start() async {
    controller = StreamController<Uint8List>();
    return controller!.stream;
  }

  @override
  Future<void> stop() async => controller?.close();
  @override
  Future<void> dispose() async {}
}

void main() {
  testWidgets('host screen starts sharing, shows code + QR, and stops',
      (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() => tester.view.reset());
    final container = ProviderContainer(overrides: [
      storageProvider.overrideWithValue(StorageService()),
      audioCaptureSourceProvider.overrideWithValue(_FakeMic()),
      peerHostOptionsProvider.overrideWithValue(PeerHostOptions(
        bindAddress: InternetAddress.loopbackIPv4,
        httpPort: 0,
        discoveryPort: 0,
        useForegroundService: false,
      )),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: AppTheme.dark, home: const HostScreen()),
    ));
    // Config load is async (in-memory storage) — let it settle.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    expect(find.text('Start sharing microphone'), findsOneWidget);
    expect(find.text('Phone camera'), findsWidgets);

    // Start via the notifier under runAsync (real sockets), then let the UI
    // catch up.
    await tester.runAsync(() => container.read(peerHostProvider.notifier).start());
    await tester.pump();
    final state = container.read(peerHostProvider);
    expect(state.isRunning, isTrue);
    expect(find.text('Stop sharing'), findsOneWidget);
    expect(find.text('Pairing code'), findsOneWidget);
    // The formatted code ("123 456") is on screen.
    final shown = '${state.code.substring(0, 3)} ${state.code.substring(3)}';
    expect(find.text(shown), findsOneWidget);
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.textContaining('127.0.0.1:${state.port}'), findsOneWidget);
    expect(find.text('No phone has paired yet.'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.runAsync(() => container.read(peerHostProvider.notifier).stop());
    await tester.pump();
    expect(find.text('Start sharing microphone'), findsOneWidget);
    expect(find.byType(QrImageView), findsNothing);
  });
}
