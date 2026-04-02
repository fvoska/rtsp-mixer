import 'package:flutter_test/flutter_test.dart';

import 'package:rtsp_audio_mixer/core/storage/secure_storage_service.dart';

import 'fake_flutter_secure_storage.dart';

void main() {
  late FakeFlutterSecureStorage fakeStorage;
  late SecureStorageService service;

  setUp(() {
    fakeStorage = FakeFlutterSecureStorage();
    service = SecureStorageService(fakeStorage);
  });

  group('SecureStorageService', () {
    group('credentials', () {
      test('saves and retrieves credentials', () async {
        await service.saveCredentials('192.168.1.1', 'admin', 'pass123');

        final creds = await service.loadCredentials();

        expect(creds, isNotNull);
        expect(creds!.host, '192.168.1.1');
        expect(creds.username, 'admin');
        expect(creds.password, 'pass123');
      });

      test('returns null when no credentials saved', () async {
        final creds = await service.loadCredentials();
        expect(creds, isNull);
      });

      test('returns null when only some keys are saved', () async {
        fakeStorage.data['protect_host'] = '192.168.1.1';
        // username and password not saved

        final creds = await service.loadCredentials();
        expect(creds, isNull);
      });

      test('clearCredentials removes all keys', () async {
        await service.saveCredentials('192.168.1.1', 'admin', 'pass123');
        await service.saveSelectedCameraIds(['cam-001']);
        await service.saveSslAccepted('192.168.1.1', true);

        await service.clearCredentials();

        final creds = await service.loadCredentials();
        expect(creds, isNull);

        final ids = await service.loadSelectedCameraIds();
        expect(ids, isEmpty);
      });
    });

    group('selected camera IDs', () {
      test('saves and retrieves camera IDs', () async {
        await service.saveSelectedCameraIds(['cam-001', 'cam-002']);

        final ids = await service.loadSelectedCameraIds();

        expect(ids, ['cam-001', 'cam-002']);
      });

      test('returns empty list when no IDs saved', () async {
        final ids = await service.loadSelectedCameraIds();
        expect(ids, isEmpty);
      });

      test('handles empty list', () async {
        await service.saveSelectedCameraIds([]);

        final ids = await service.loadSelectedCameraIds();
        expect(ids, isEmpty);
      });
    });

    group('SSL acceptance', () {
      test('saves and retrieves SSL acceptance per host', () async {
        await service.saveSslAccepted('192.168.1.1', true);

        final accepted = await service.loadSslAccepted('192.168.1.1');
        expect(accepted, isTrue);
      });

      test('returns false for unknown host', () async {
        final accepted = await service.loadSslAccepted('10.0.0.1');
        expect(accepted, isFalse);
      });

      test('stores per-host independently', () async {
        await service.saveSslAccepted('192.168.1.1', true);
        await service.saveSslAccepted('10.0.0.1', false);

        expect(await service.loadSslAccepted('192.168.1.1'), isTrue);
        expect(await service.loadSslAccepted('10.0.0.1'), isFalse);
      });
    });
  });
}
