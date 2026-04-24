import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rtsp_mixer/features/monitoring/services/reconnect_supervisor.dart';

void main() {
  group('ReconnectSupervisor dedupe (Pattern 3)', () {
    test('two simultaneous requests for the same camera produce one attempt',
        () {
      fakeAsync((async) {
        var attempts = 0;
        final sup = ReconnectSupervisor(
          onAttempt: (_) async => attempts++,
          onStatusChange: (_, __) {},
          onEvent: (_, __, ___) {},
        );
        // First call enters, schedules retry. Second is suppressed because
        // a retry is already scheduled for this cameraId.
        sup.requestReconnect('cam1', cause: 'player_error');
        sup.requestReconnect('cam1', cause: 'zombie');
        async.elapse(const Duration(seconds: 2));
        expect(attempts, 1);
      });
    });

    test('different cameras do NOT dedupe each other', () {
      fakeAsync((async) {
        var attemptsCam1 = 0;
        var attemptsCam2 = 0;
        final sup = ReconnectSupervisor(
          onAttempt: (id) async =>
              id == 'cam1' ? attemptsCam1++ : attemptsCam2++,
          onStatusChange: (_, __) {},
          onEvent: (_, __, ___) {},
        );
        sup.requestReconnect('cam1', cause: 'player_error');
        sup.requestReconnect('cam2', cause: 'player_error');
        async.elapse(const Duration(seconds: 2));
        expect(attemptsCam1, 1);
        expect(attemptsCam2, 1);
      });
    });
  });
}
