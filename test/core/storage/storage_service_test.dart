import 'package:flutter_test/flutter_test.dart';
import 'package:rtsp_mixer/core/storage/storage_service.dart';

void main() {
  late StorageService storage;

  setUp(() => storage = StorageService());

  group('StorageService', () {
    group('credentials', () {
      test('saves and loads credentials', () async {
        await storage.saveCredentials('192.168.1.1', 'my-key');
        final creds = await storage.loadCredentials();
        expect(creds, isNotNull);
        expect(creds!.host, '192.168.1.1');
        expect(creds.apiKey, 'my-key');
      });

      test('returns null when no credentials saved', () async {
        expect(await storage.loadCredentials(), isNull);
      });

      test('clearAll removes everything', () async {
        await storage.saveCredentials('10.0.0.1', 'key');
        await storage.saveSelectedCameraIds(['cam-1']);
        await storage.clearAll();
        expect(await storage.loadCredentials(), isNull);
        expect(await storage.loadSelectedCameraIds(), isEmpty);
      });
    });

    group('remote host', () {
      test('save then load round-trips', () async {
        await storage.saveRemoteHost('100.64.0.9');
        expect(await storage.loadRemoteHost(), '100.64.0.9');
      });

      test('returns null when never saved', () async {
        expect(await storage.loadRemoteHost(), isNull);
      });

      test('delete then load returns null', () async {
        await storage.saveRemoteHost('100.64.0.9');
        await storage.deleteRemoteHost();
        expect(await storage.loadRemoteHost(), isNull);
      });
    });

    group('selected cameras', () {
      test('saves and loads camera IDs', () async {
        await storage.saveSelectedCameraIds(['cam-1', 'cam-2']);
        expect(await storage.loadSelectedCameraIds(), ['cam-1', 'cam-2']);
      });

      test('returns empty list when none saved', () async {
        expect(await storage.loadSelectedCameraIds(), isEmpty);
      });
    });
  });
  peerStorageTests();
}

void peerStorageTests() {
  late StorageService storage;
  setUp(() => storage = StorageService());

  group('peer storage', () {
    test('peer cameras round-trip and tolerate garbage', () async {
      expect(await storage.loadPeerCameras(), isEmpty);
      await storage.savePeerCameras([{'id': 'peer-1', 'source': 'peer'}]);
      expect((await storage.loadPeerCameras()).single['id'], 'peer-1');
      await storage.write('peer_cameras', 'not json');
      expect(await storage.loadPeerCameras(), isEmpty);
    });

    test('peer host config round-trips and tolerates garbage', () async {
      expect(await storage.loadPeerHostConfig(), isNull);
      await storage.savePeerHostConfig({'hostId': 'h', 'name': 'Nursery'});
      expect((await storage.loadPeerHostConfig())!['name'], 'Nursery');
      await storage.write('peer_host_config', '[1,2');
      expect(await storage.loadPeerHostConfig(), isNull);
    });
  });
}
