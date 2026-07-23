import 'package:flutter_test/flutter_test.dart';
import 'package:rtsp_mixer/features/cameras/models/protect_camera.dart';
import 'package:rtsp_mixer/features/monitoring/models/player_state.dart';
import 'package:rtsp_mixer/features/monitoring/providers/audio_player_provider.dart';

/// Tests for audio player state logic.
/// Since Player requires native libraries, these test the pure state
/// transitions using CameraAudioState and MonitoringState directly.
void main() {
  group('CameraAudioState volume logic', () {
    test('effectiveVolume returns volume when not muted', () {
      const state = CameraAudioState(
        cameraId: 'cam1',
        cameraName: 'Nursery',
        volume: 75.0,
      );
      expect(state.effectiveVolume, 75.0);
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

    test('setVolume updates volume and preMuteVolume via copyWith', () {
      const state = CameraAudioState(
        cameraId: 'cam1',
        cameraName: 'Nursery',
        volume: 100.0,
      );
      final updated = state.copyWith(volume: 50.0, preMuteVolume: 50.0);
      expect(updated.volume, 50.0);
      expect(updated.preMuteVolume, 50.0);
      expect(updated.effectiveVolume, 50.0);
    });

    test('mute sets isMuted true and stores preMuteVolume', () {
      const state = CameraAudioState(
        cameraId: 'cam1',
        cameraName: 'Nursery',
        volume: 80.0,
      );
      final muted = state.copyWith(isMuted: true, preMuteVolume: 80.0);
      expect(muted.isMuted, true);
      expect(muted.effectiveVolume, 0.0);
      expect(muted.preMuteVolume, 80.0);
    });

    test('unmute restores preMuteVolume as effectiveVolume', () {
      const muted = CameraAudioState(
        cameraId: 'cam1',
        cameraName: 'Nursery',
        volume: 80.0,
        isMuted: true,
        preMuteVolume: 80.0,
      );
      final unmuted = muted.copyWith(isMuted: false);
      expect(unmuted.isMuted, false);
      expect(unmuted.effectiveVolume, 80.0);
      expect(unmuted.preMuteVolume, 80.0);
    });
  });

  group('CameraAudioState pan logic', () {
    test('pan defaults to 0.0 (center)', () {
      const state = CameraAudioState(
        cameraId: 'cam1',
        cameraName: 'Nursery',
      );
      expect(state.pan, 0.0);
    });

    test('setPan updates pan value via copyWith', () {
      const state = CameraAudioState(
        cameraId: 'cam1',
        cameraName: 'Nursery',
      );
      final panned = state.copyWith(pan: -0.7);
      expect(panned.pan, -0.7);
    });

    test('pan can be set to full left', () {
      const state = CameraAudioState(
        cameraId: 'cam1',
        cameraName: 'Nursery',
      );
      final panned = state.copyWith(pan: -1.0);
      expect(panned.pan, -1.0);
    });

    test('pan can be set to full right', () {
      const state = CameraAudioState(
        cameraId: 'cam1',
        cameraName: 'Nursery',
      );
      final panned = state.copyWith(pan: 1.0);
      expect(panned.pan, 1.0);
    });
  });

  group('MonitoringState camera updates', () {
    test('copyWithCamera updates correct camera at index', () {
      const monitoring = MonitoringState(cameras: [
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

      final updated = monitoring.copyWithCamera(
        0,
        monitoring.cameras[0].copyWith(volume: 30.0),
      );

      expect(updated.cameras[0].volume, 30.0);
      expect(updated.cameras[1].volume, 100.0);
    });

    test('copyWithCamera preserves other camera state', () {
      const monitoring = MonitoringState(cameras: [
        CameraAudioState(
          cameraId: 'cam1',
          cameraName: 'Nursery',
          volume: 50.0,
          pan: -0.5,
        ),
        CameraAudioState(
          cameraId: 'cam2',
          cameraName: 'Bedroom',
          volume: 75.0,
          pan: 0.3,
        ),
      ]);

      final updated = monitoring.copyWithCamera(
        1,
        monitoring.cameras[1].copyWith(isMuted: true, preMuteVolume: 75.0),
      );

      expect(updated.cameras[0].volume, 50.0);
      expect(updated.cameras[0].pan, -0.5);
      expect(updated.cameras[1].isMuted, true);
      expect(updated.cameras[1].preMuteVolume, 75.0);
    });

    test('volume change on one camera does not affect the other', () {
      const monitoring = MonitoringState(cameras: [
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

      final step1 = monitoring.copyWithCamera(
        0,
        monitoring.cameras[0].copyWith(volume: 25.0, preMuteVolume: 25.0),
      );
      final step2 = step1.copyWithCamera(
        1,
        step1.cameras[1].copyWith(volume: 80.0, preMuteVolume: 80.0),
      );

      expect(step2.cameras[0].volume, 25.0);
      expect(step2.cameras[1].volume, 80.0);
    });
  });

  group('addableCameras', () {
    ProtectCamera cam(String id) =>
        ProtectCamera(id: id, name: id, state: 'CONNECTED');
    CameraAudioState inMix(String id) =>
        CameraAudioState(cameraId: id, cameraName: id);

    test('returns only cameras not already in the session', () {
      final all = [cam('a'), cam('b'), cam('c')];
      final result = addableCameras(all, [inMix('a')]);
      expect(result.map((c) => c.id).toList(), ['b', 'c']);
    });

    test('is empty when every camera is already in the mix', () {
      final all = [cam('a'), cam('b')];
      final result = addableCameras(all, [inMix('a'), inMix('b')]);
      expect(result, isEmpty);
    });

    test('returns all cameras when the session is empty', () {
      final all = [cam('a'), cam('b')];
      expect(addableCameras(all, const []).map((c) => c.id).toList(),
          ['a', 'b']);
    });

    test('is empty when the camera list is empty', () {
      expect(addableCameras(const [], [inMix('a')]), isEmpty);
    });
  });
}
