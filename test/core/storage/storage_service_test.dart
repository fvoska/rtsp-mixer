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
}
