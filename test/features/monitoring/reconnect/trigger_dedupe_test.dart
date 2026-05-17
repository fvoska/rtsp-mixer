import 'dart:async';
import 'dart:math';

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
          onStatusChange: (_, _) {},
          onEvent: (_, _, _) {},
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
          onStatusChange: (_, _) {},
          onEvent: (_, _, _) {},
        );
        sup.requestReconnect('cam1', cause: 'player_error');
        sup.requestReconnect('cam2', cause: 'player_error');
        async.elapse(const Duration(seconds: 2));
        expect(attemptsCam1, 1);
        expect(attemptsCam2, 1);
      });
    });

    test(
        'CR-02: immediate=true cancels pending retry timer and attempts now '
        '(WiFi-back bypass)', () {
      fakeAsync((async) {
        var attempts = 0;
        // Use a fixed-seed Random so backoff is deterministic across runs.
        final sup = ReconnectSupervisor(
          random: Random(42),
          onAttempt: (_) async {
            attempts++;
            // First attempt fails to seed a backoff timer; following succeed.
            if (attempts == 1) {
              throw StateError('seed failure');
            }
          },
          onStatusChange: (_, _) {},
          onEvent: (_, _, _) {},
        );
        // First trigger: seeds attempt 0, fires after ~1s backoff (jittered).
        sup.requestReconnect('cam1', cause: 'player_error');
        // Elapse enough for attempt 0 to fire and fail (~1.2s upper bound),
        // but NOT enough for attempt 1's retry (~2s base) to fire yet.
        async.elapse(const Duration(milliseconds: 1500));
        expect(attempts, 1,
            reason: 'seed attempt should have fired and failed exactly once');
        expect(sup.hasPendingRetry('cam1'), true,
            reason: 'a retry should be scheduled after the failure');

        // Now: WiFi-back trigger arrives while a backoff retry is pending.
        // Without CR-02 fix this would be suppressed and the camera would
        // wait the full backoff. With the fix the immediate flag cancels
        // the pending timer and attempts now.
        sup.requestReconnect('cam1',
            cause: 'wifi_reconnect', immediate: true);
        async.flushMicrotasks();
        expect(attempts, 2,
            reason: 'immediate=true must bypass the pending backoff timer');
        expect(sup.hasPendingRetry('cam1'), false,
            reason: 'pending retry should be cancelled');
      });
    });

    test('immediate=true is suppressed when an attempt is currently in-flight',
        () {
      fakeAsync((async) {
        var attempts = 0;
        final completer = Completer<void>();
        final sup = ReconnectSupervisor(
          onAttempt: (_) async {
            attempts++;
            // Block the first attempt so a second `immediate` request arrives
            // while inFlight=true.
            if (attempts == 1) {
              await completer.future;
            }
          },
          onStatusChange: (_, _) {},
          onEvent: (_, _, _) {},
        );
        sup.requestReconnect('cam1',
            cause: 'wifi_reconnect', immediate: true);
        async.flushMicrotasks();
        // First attempt is blocked; second immediate request must be suppressed.
        sup.requestReconnect('cam1',
            cause: 'wifi_reconnect', immediate: true);
        async.flushMicrotasks();
        expect(attempts, 1);
        // Unblock the first attempt to clean up.
        completer.complete();
        async.flushMicrotasks();
      });
    });
  });
}
