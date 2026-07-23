import 'package:flutter_test/flutter_test.dart';
import 'package:rtsp_mixer/features/cameras/models/protect_camera.dart';

void main() {
  group('ProtectCamera remoteUrl', () {
    test('remoteUrl survives toJson/fromJson round-trip', () {
      final cam = ProtectCamera.manual(
        id: 'm1',
        url: 'rtsp://192.168.1.50:554/stream',
        name: 'Nursery',
        remoteUrl: 'rtsp://100.64.0.9:554/stream',
      );
      final restored = ProtectCamera.fromJson(cam.toJson());
      expect(restored.remoteUrl, 'rtsp://100.64.0.9:554/stream');
      expect(restored.defaultStreamUrl, 'rtsp://192.168.1.50:554/stream');
      expect(restored.isManual, true);
      expect(restored.name, 'Nursery');
    });

    test('legacy JSON without the remoteUrl key deserializes with null', () {
      final cam = ProtectCamera.fromJson({
        'id': 'legacy',
        'state': 'CONNECTED',
        'source': 'manual',
        'rtspsStreamUrls': {'stream': 'rtsp://h/s'},
      });
      expect(cam.remoteUrl, isNull);
    });

    test('remoteUrl defaults to null on manual factory', () {
      final cam = ProtectCamera.manual(id: 'm1', url: 'rtsp://h/s');
      expect(cam.remoteUrl, isNull);
    });

    test('copyWith can set remoteUrl', () {
      final cam = ProtectCamera.manual(id: 'm1', url: 'rtsp://h/s');
      final updated = cam.copyWith(remoteUrl: 'rtsp://remote/s');
      expect(updated.remoteUrl, 'rtsp://remote/s');
      // unrelated fields preserved
      expect(updated.id, 'm1');
      expect(updated.source, CameraSource.manual);
      expect(updated.defaultStreamUrl, 'rtsp://h/s');
    });

    test('copyWith preserves remoteUrl when not specified', () {
      final cam = ProtectCamera.manual(
        id: 'm1',
        url: 'rtsp://h/s',
        remoteUrl: 'rtsp://remote/s',
      );
      final updated = cam.copyWith(rtspsStreamUrls: {'stream': 'rtsp://h/x'});
      expect(updated.remoteUrl, 'rtsp://remote/s');
    });

    test('copyWith can clear remoteUrl to null', () {
      final cam = ProtectCamera.manual(
        id: 'm1',
        url: 'rtsp://h/s',
        remoteUrl: 'rtsp://remote/s',
      );
      final updated = cam.copyWith(remoteUrl: null);
      expect(updated.remoteUrl, isNull);
    });

    test('round-trip of a camera without remoteUrl keeps it null', () {
      final cam = ProtectCamera.manual(id: 'm1', url: 'rtsp://h/s');
      final restored = ProtectCamera.fromJson(cam.toJson());
      expect(restored.remoteUrl, isNull);
    });
  });
}
