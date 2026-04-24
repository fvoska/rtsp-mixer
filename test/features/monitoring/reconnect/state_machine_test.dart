import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rtsp_mixer/features/monitoring/services/reconnect_supervisor.dart';

void main() {
  group('ReconnectSupervisor state machine (RELY-02 transitions)', () {
    test('successful reconnect emits reconnecting -> playing and resets attempt',
        () {
      fakeAsync((async) {
        final statuses = <ReconnectStatus>[];
        final events = <ReconnectEventType>[];
        final sup = ReconnectSupervisor(
          onAttempt: (_) async {}, // success
          onStatusChange: (_, s) => statuses.add(s),
          onEvent: (t, _, __) => events.add(t),
        );
        sup.requestReconnect('cam1', cause: 'player_error');
        async.elapse(const Duration(seconds: 2));
        expect(statuses, [
          ReconnectStatus.reconnecting,
          ReconnectStatus.playing,
        ]);
        expect(events, [
          ReconnectEventType.reconnectAttempt,
          ReconnectEventType.reconnectSuccess,
        ]);
        expect(sup.attemptCount('cam1'), 0);
      });
    });

    test('cancelAll cancels pending retryTimers (no attempts fire after cancel)',
        () {
      fakeAsync((async) {
        var attempts = 0;
        final sup = ReconnectSupervisor(
          onAttempt: (_) async {
            attempts++;
            throw StateError('fail'); // force re-schedule
          },
          onStatusChange: (_, __) {},
          onEvent: (_, __, ___) {},
        );
        sup.requestReconnect('cam1', cause: 'player_error');
        async.elapse(const Duration(seconds: 2)); // attempt 0 fires
        expect(attempts, 1);
        sup.cancelAll();
        async.elapse(const Duration(seconds: 120)); // should NOT fire again
        expect(attempts, 1);
        expect(sup.hasPendingRetry('cam1'), false);
      });
    });
  });
}
