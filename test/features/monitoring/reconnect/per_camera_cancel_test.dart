import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rtsp_mixer/features/monitoring/services/reconnect_supervisor.dart';

void main() {
  group('ReconnectSupervisor.cancel(cameraId)', () {
    test('cancels the pending retryTimer for that camera only', () {
      fakeAsync((async) {
        final attempts = <String>[];
        final sup = ReconnectSupervisor(
          onAttempt: (id) async {
            attempts.add(id);
            throw StateError('keep failing'); // force re-schedule
          },
          onStatusChange: (_, __) {},
          onEvent: (_, __, ___) {},
        );

        sup.requestReconnect('cam1', cause: 'test');
        sup.requestReconnect('cam2', cause: 'test');
        // Let the first attempts fire.
        async.elapse(const Duration(seconds: 2));
        expect(attempts, ['cam1', 'cam2']);

        // Cancel only cam1. cam2 should still attempt again.
        sup.cancel('cam1');
        attempts.clear();
        async.elapse(const Duration(seconds: 30));
        expect(attempts.contains('cam1'), isFalse,
            reason: 'cancel(cam1) must stop further cam1 attempts');
        expect(attempts.contains('cam2'), isTrue,
            reason: 'cancel(cam1) must NOT affect cam2');
      });
    });

    test('clears attempt counter for the cancelled camera', () {
      fakeAsync((async) {
        final sup = ReconnectSupervisor(
          onAttempt: (_) async => throw StateError('fail'),
          onStatusChange: (_, __) {},
          onEvent: (_, __, ___) {},
        );
        sup.requestReconnect('cam1', cause: 'test');
        async.elapse(const Duration(seconds: 10));
        expect(sup.attemptCount('cam1'), greaterThan(0));
        sup.cancel('cam1');
        expect(sup.attemptCount('cam1'), 0,
            reason: 'per-camera state is forgotten after cancel');
        expect(sup.hasPendingRetry('cam1'), isFalse);
      });
    });
  });
}
