import 'package:flutter_test/flutter_test.dart';
import 'package:rtsp_mixer/features/monitoring/models/player_state.dart';

void main() {
  group('CameraAudioState', () {
    test('default values are volume=100, pan=0, isMuted=false, idle', () {
      const state = CameraAudioState(
        cameraId: 'cam1',
        cameraName: 'Nursery',
      );
      expect(state.volume, 100.0);
      expect(state.pan, 0.0);
      expect(state.isMuted, false);
      expect(state.connectionStatus, CameraConnectionStatus.idle);
    });

    test('effectiveVolume returns 0.0 when muted', () {
      const state = CameraAudioState(
        cameraId: 'cam1',
        cameraName: 'Nursery',
        volume: 75.0,
        isMuted: true,
      );
      expect(state.effectiveVolume, 0.0);
    });

    test('effectiveVolume returns volume value when not muted', () {
      const state = CameraAudioState(
        cameraId: 'cam1',
        cameraName: 'Nursery',
        volume: 75.0,
        isMuted: false,
      );
      expect(state.effectiveVolume, 75.0);
    });

    test('copyWith preserves cameraId and cameraName', () {
      const original = CameraAudioState(
        cameraId: 'cam1',
        cameraName: 'Nursery',
      );
      final updated = original.copyWith(volume: 50.0, pan: -0.5);
      expect(updated.cameraId, 'cam1');
      expect(updated.cameraName, 'Nursery');
      expect(updated.volume, 50.0);
      expect(updated.pan, -0.5);
    });

    test('isLive returns true only when playing', () {
      const playing = CameraAudioState(
        cameraId: 'cam1',
        cameraName: 'Nursery',
        connectionStatus: CameraConnectionStatus.playing,
      );
      const idle = CameraAudioState(
        cameraId: 'cam1',
        cameraName: 'Nursery',
        connectionStatus: CameraConnectionStatus.idle,
      );
      expect(playing.isLive, true);
      expect(idle.isLive, false);
    });

    test('isError returns true only when error status', () {
      const error = CameraAudioState(
        cameraId: 'cam1',
        cameraName: 'Nursery',
        connectionStatus: CameraConnectionStatus.error,
        errorMessage: 'Connection failed',
      );
      expect(error.isError, true);
    });
  });

  group('MonitoringState', () {
    test('allLive returns true only when all cameras are playing', () {
      const state = MonitoringState(cameras: [
        CameraAudioState(
          cameraId: 'cam1',
          cameraName: 'Nursery',
          connectionStatus: CameraConnectionStatus.playing,
        ),
        CameraAudioState(
          cameraId: 'cam2',
          cameraName: 'Bedroom',
          connectionStatus: CameraConnectionStatus.playing,
        ),
      ]);
      expect(state.allLive, true);
    });

    test('allLive returns false when one camera is not playing', () {
      const state = MonitoringState(cameras: [
        CameraAudioState(
          cameraId: 'cam1',
          cameraName: 'Nursery',
          connectionStatus: CameraConnectionStatus.playing,
        ),
        CameraAudioState(
          cameraId: 'cam2',
          cameraName: 'Bedroom',
          connectionStatus: CameraConnectionStatus.connecting,
        ),
      ]);
      expect(state.allLive, false);
    });

    test('anyError returns true when any camera has error status', () {
      const state = MonitoringState(cameras: [
        CameraAudioState(
          cameraId: 'cam1',
          cameraName: 'Nursery',
          connectionStatus: CameraConnectionStatus.playing,
        ),
        CameraAudioState(
          cameraId: 'cam2',
          cameraName: 'Bedroom',
          connectionStatus: CameraConnectionStatus.error,
        ),
      ]);
      expect(state.anyError, true);
    });

    test('copyWithCamera returns new state with updated camera at index', () {
      const original = MonitoringState(cameras: [
        CameraAudioState(
          cameraId: 'cam1',
          cameraName: 'Nursery',
          volume: 100.0,
        ),
        CameraAudioState(
          cameraId: 'cam2',
          cameraName: 'Bedroom',
          volume: 100.0,
        ),
      ]);
      final updated = original.copyWithCamera(
        0,
        original.cameras[0].copyWith(volume: 50.0),
      );
      expect(updated.cameras[0].volume, 50.0);
      expect(updated.cameras[1].volume, 100.0);
    });
  });
}
