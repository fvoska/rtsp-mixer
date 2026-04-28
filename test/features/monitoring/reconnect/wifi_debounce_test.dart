import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rtsp_mixer/features/monitoring/services/connectivity_listener.dart';

void main() {
  group('ConnectivityListener (D-03 trigger c + RESEARCH §Section 3)', () {
    late StreamController<List<ConnectivityResult>> controller;
    late int dropped;
    late int reconnected;
    late ConnectivityListener listener;

    setUp(() {
      controller = StreamController<List<ConnectivityResult>>.broadcast();
      dropped = 0;
      reconnected = 0;
      listener = ConnectivityListener(
        stream: controller.stream,
        onDropped: () => dropped++,
        onReconnected: () => reconnected++,
      );
    });

    tearDown(() async {
      listener.cancel();
      await controller.close();
    });

    test('three rapid flaps within 500ms collapse to one effective transition',
        () {
      fakeAsync((async) {
        listener.start();
        controller.add([ConnectivityResult.wifi]);
        async.elapse(const Duration(milliseconds: 100));
        controller.add([ConnectivityResult.none]);
        async.elapse(const Duration(milliseconds: 100));
        controller.add([ConnectivityResult.wifi]);
        async.elapse(const Duration(milliseconds: 100));
        controller.add([ConnectivityResult.none]);
        async.elapse(const Duration(milliseconds: 1100));
        expect(dropped, 1);
        expect(reconnected, 0);
      });
    });

    test('[wifi] -> [none] triggers onDropped once after debounce', () {
      fakeAsync((async) {
        listener.start();
        controller.add([ConnectivityResult.wifi]);
        async.elapse(const Duration(milliseconds: 1100));
        controller.add([ConnectivityResult.none]);
        async.elapse(const Duration(milliseconds: 1100));
        expect(dropped, 1);
      });
    });

    test('[none] -> [wifi] triggers onReconnected once after debounce', () {
      fakeAsync((async) {
        listener.start();
        controller.add([ConnectivityResult.none]);
        async.elapse(const Duration(milliseconds: 1100));
        controller.add([ConnectivityResult.wifi]);
        async.elapse(const Duration(milliseconds: 1100));
        expect(reconnected, 1);
      });
    });

    test('[none] -> [mobile] does NOT trigger onReconnected (mobile != LAN)',
        () {
      fakeAsync((async) {
        listener.start();
        controller.add([ConnectivityResult.none]);
        async.elapse(const Duration(milliseconds: 1100));
        controller.add([ConnectivityResult.mobile]);
        async.elapse(const Duration(milliseconds: 1100));
        expect(reconnected, 0);
      });
    });

    test('[wifi] -> [wifi] is a no-op', () {
      fakeAsync((async) {
        listener.start();
        controller.add([ConnectivityResult.wifi]);
        async.elapse(const Duration(milliseconds: 1100));
        controller.add([ConnectivityResult.wifi]);
        async.elapse(const Duration(milliseconds: 1100));
        expect(dropped, 0);
        expect(reconnected, 0);
      });
    });

    test('ethernet counts as LAN (macOS dev builds)', () {
      fakeAsync((async) {
        listener.start();
        controller.add([ConnectivityResult.none]);
        async.elapse(const Duration(milliseconds: 1100));
        controller.add([ConnectivityResult.ethernet]);
        async.elapse(const Duration(milliseconds: 1100));
        expect(reconnected, 1);
      });
    });

    test('cancel() stops delivery — no callbacks after cancel', () {
      fakeAsync((async) {
        listener.start();
        controller.add([ConnectivityResult.wifi]);
        async.elapse(const Duration(milliseconds: 1100));
        listener.cancel();
        controller.add([ConnectivityResult.none]);
        async.elapse(const Duration(milliseconds: 2000));
        expect(dropped, 0);
        expect(reconnected, 0);
      });
    });
  });
}
