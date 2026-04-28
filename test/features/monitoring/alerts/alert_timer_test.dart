import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rtsp_mixer/features/monitoring/services/alert_policy.dart';

void main() {
  group('AlertPolicy (D-04: 5-min one-shot per camera)', () {
    test('fires exactly once after 5 minutes of continuous non-playing', () {
      fakeAsync((async) {
        final fired = <String>[];
        final policy = AlertPolicy(onFire: fired.add);
        policy.armIfAbsent('cam1');
        async.elapse(const Duration(minutes: 4, seconds: 59));
        expect(fired, isEmpty);
        async.elapse(const Duration(seconds: 2));
        expect(fired, ['cam1']);
        expect(policy.hasFired('cam1'), true);
        expect(policy.isArmed('cam1'), false);
      });
    });

    test('clear() cancels pending Timer before fire', () {
      fakeAsync((async) {
        final fired = <String>[];
        final policy = AlertPolicy(onFire: fired.add);
        policy.armIfAbsent('cam1');
        async.elapse(const Duration(minutes: 2));
        policy.clear('cam1');
        async.elapse(const Duration(minutes: 10));
        expect(fired, isEmpty);
        expect(policy.hasFired('cam1'), false);
      });
    });

    test('armIfAbsent during active timer does NOT reset the clock', () {
      fakeAsync((async) {
        final fired = <String>[];
        final policy = AlertPolicy(onFire: fired.add);
        policy.armIfAbsent('cam1');
        async.elapse(const Duration(minutes: 4));
        policy.armIfAbsent('cam1'); // no-op
        async.elapse(const Duration(seconds: 61));
        expect(fired, ['cam1']);
      });
    });

    test('return-to-playing resets flag — next outage can fire again', () {
      fakeAsync((async) {
        final fired = <String>[];
        final policy = AlertPolicy(onFire: fired.add);
        // First outage: fire
        policy.armIfAbsent('cam1');
        async.elapse(const Duration(minutes: 5, seconds: 1));
        expect(fired, ['cam1']);
        // Recovery
        policy.clear('cam1');
        // Second outage
        policy.armIfAbsent('cam1');
        async.elapse(const Duration(minutes: 5, seconds: 1));
        expect(fired, ['cam1', 'cam1']);
      });
    });

    test('per-camera independence — two outages fire two separate events', () {
      fakeAsync((async) {
        final fired = <String>[];
        final policy = AlertPolicy(onFire: fired.add);
        policy.armIfAbsent('cam1');
        async.elapse(const Duration(minutes: 2));
        policy.armIfAbsent('cam2');
        async.elapse(const Duration(minutes: 3, seconds: 1));
        expect(fired, ['cam1']); // cam1 at T+5:01
        async.elapse(const Duration(minutes: 2, seconds: 1));
        expect(fired, ['cam1', 'cam2']); // cam2 at T+7:02
      });
    });

    test('cancelAll() tears down all pending Timers and flags', () {
      fakeAsync((async) {
        final fired = <String>[];
        final policy = AlertPolicy(onFire: fired.add);
        policy.armIfAbsent('cam1');
        policy.armIfAbsent('cam2');
        async.elapse(const Duration(minutes: 3));
        policy.cancelAll();
        async.elapse(const Duration(minutes: 10));
        expect(fired, isEmpty);
        expect(policy.isArmed('cam1'), false);
        expect(policy.isArmed('cam2'), false);
      });
    });
  });
}
