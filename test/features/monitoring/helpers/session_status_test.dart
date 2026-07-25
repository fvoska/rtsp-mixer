import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rtsp_mixer/features/monitoring/helpers/session_status.dart';
import 'package:rtsp_mixer/features/monitoring/models/player_state.dart';

CameraAudioState _cam(
  CameraConnectionStatus status, {
  String id = 'cam1',
  String name = 'Nursery',
}) =>
    CameraAudioState(
      cameraId: id,
      cameraName: name,
      connectionStatus: status,
      activeQuality: 'low',
      availableQualities: const {'low': 'a'},
    );

void main() {
  group('sessionStatusOf', () {
    test('all playing is the only healthy result', () {
      expect(
        sessionStatusOf([
          _cam(CameraConnectionStatus.playing),
          _cam(CameraConnectionStatus.playing, id: 'cam2'),
        ]),
        SessionStatus.playing,
      );
    });

    test('an empty mix is connecting, never playing', () {
      expect(sessionStatusOf(const []), SessionStatus.connecting);
    });

    test('error wins over a healthy sibling', () {
      expect(
        sessionStatusOf([
          _cam(CameraConnectionStatus.playing),
          _cam(CameraConnectionStatus.error, id: 'cam2'),
        ]),
        SessionStatus.error,
      );
    });

    test('error wins over reconnecting', () {
      expect(
        sessionStatusOf([
          _cam(CameraConnectionStatus.reconnecting),
          _cam(CameraConnectionStatus.error, id: 'cam2'),
        ]),
        SessionStatus.error,
      );
    });

    test('reconnecting is distinguished from a first connection', () {
      expect(
        sessionStatusOf([
          _cam(CameraConnectionStatus.playing),
          _cam(CameraConnectionStatus.reconnecting, id: 'cam2'),
        ]),
        SessionStatus.reconnecting,
      );
      expect(
        sessionStatusOf([
          _cam(CameraConnectionStatus.playing),
          _cam(CameraConnectionStatus.connecting, id: 'cam2'),
        ]),
        SessionStatus.connecting,
      );
    });

    test('idle cameras are not live', () {
      expect(
        sessionStatusOf([_cam(CameraConnectionStatus.idle)]),
        SessionStatus.connecting,
      );
    });
  });

  group('resolveSessionStatus', () {
    test('a loading provider is connecting, not playing', () {
      expect(
        resolveSessionStatus(const AsyncValue<MonitoringState>.loading()),
        SessionStatus.connecting,
      );
    });

    test('a provider error is a session error', () {
      expect(
        resolveSessionStatus(
          AsyncValue<MonitoringState>.error('boom', StackTrace.empty),
        ),
        SessionStatus.error,
      );
    });

    test('delegates to sessionStatusOf for data', () {
      expect(
        resolveSessionStatus(AsyncValue.data(
          MonitoringState(cameras: [_cam(CameraConnectionStatus.playing)]),
        )),
        SessionStatus.playing,
      );
    });
  });

  group('labels', () {
    test('only playing claims the session is active / listening', () {
      expect(sessionStatusLabel(SessionStatus.playing), 'Monitoring active');
      expect(sessionNotificationTitle(SessionStatus.playing), 'Listening');
      for (final degraded in [
        SessionStatus.connecting,
        SessionStatus.reconnecting,
        SessionStatus.error,
      ]) {
        expect(sessionStatusLabel(degraded), isNot(contains('active')));
        expect(sessionNotificationTitle(degraded), isNot('Listening'));
      }
    });

    test('degraded titles name the state', () {
      expect(sessionNotificationTitle(SessionStatus.connecting), 'Connecting…');
      expect(
        sessionNotificationTitle(SessionStatus.reconnecting),
        'Reconnecting…',
      );
      expect(sessionNotificationTitle(SessionStatus.error), 'Stream failed');
    });

    test('isHealthy is playing-only', () {
      expect(SessionStatus.playing.isHealthy, isTrue);
      expect(SessionStatus.connecting.isHealthy, isFalse);
      expect(SessionStatus.reconnecting.isHealthy, isFalse);
      expect(SessionStatus.error.isHealthy, isFalse);
    });
  });

  group('sessionNotificationText', () {
    test('lists names bare while playing', () {
      expect(
        sessionNotificationText([
          _cam(CameraConnectionStatus.playing, name: 'Neo'),
          _cam(CameraConnectionStatus.playing, id: 'cam2', name: 'Porch'),
        ]),
        'Monitoring: Neo, Porch',
      );
    });

    test('suffixes the non-playing cameras with their state', () {
      expect(
        sessionNotificationText([
          _cam(CameraConnectionStatus.playing, name: 'Neo'),
          _cam(CameraConnectionStatus.reconnecting, id: 'cam2', name: 'Porch'),
        ]),
        'Monitoring: Neo, Porch (reconnecting)',
      );
    });
  });
}
