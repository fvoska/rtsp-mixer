import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rtsp_mixer/features/monitoring/services/reconnect_supervisor.dart';

void main() {
  group('ReconnectSupervisor retry-forever + defensive recovery (D-02)', () {
    test('5 consecutive failures still schedule a 6th attempt', () {
      fakeAsync((async) {
        var attempts = 0;
        final sup = ReconnectSupervisor(
          onAttempt: (_) async {
            attempts++;
            throw StateError('simulated failure $attempts');
          },
          onStatusChange: (_, _) {},
          onEvent: (_, _, _) {},
        );
        sup.requestReconnect('cam1', cause: 'player_error');
        // Cumulative elapsed well past the sum of first 5 backoffs
        // (~1 + 2 + 4 + 8 + 16 + 30 worst-case + jitter). Elapse 120s total.
        async.elapse(const Duration(seconds: 120));
        expect(attempts, greaterThanOrEqualTo(5));
        expect(sup.hasPendingRetry('cam1'), true);
      });
    });

    test('an exception inside onAttempt callback does NOT kill the loop', () {
      fakeAsync((async) {
        var attempts = 0;
        final sup = ReconnectSupervisor(
          onAttempt: (_) async {
            attempts++;
            // First two throw, rest succeed.
            if (attempts <= 2) throw Exception('boom $attempts');
          },
          onStatusChange: (_, _) {},
          onEvent: (_, _, _) {},
        );
        sup.requestReconnect('cam1', cause: 'player_error');
        async.elapse(const Duration(seconds: 10));
        expect(attempts, greaterThanOrEqualTo(3));
        expect(sup.attemptCount('cam1'), 0); // reset after success
      });
    });
  });
}
